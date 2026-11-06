//! The network that says each band's gain — RNNoise's `rnn.c`: a dense
//! layer, three GRUs and a dense layer out, over int8 weights scaled by
//! 1/256 ([`model`](crate::model)).
//!
//! ⛔The voice-activity output layer is not ported: its probability is
//! what `rnnoise_process_frame` returns, and the app's one caller throws
//! it away. Its GRU stays — the noise and denoise GRUs read its state.

use crate::model::{self, Activation, Dense, Gru, TANSIG_TABLE};

const WEIGHTS_SCALE: f32 = 1.0 / 256.0;
const MAX_NEURONS: usize = 128;
pub(crate) const INPUT_SIZE: usize = 42;
pub(crate) use model::GAINS;

/// What the GRUs carry from one frame to the next.
pub(crate) struct RnnState {
    vad: [f32; model::VAD_NEURONS],
    noise: [f32; model::NOISE_NEURONS],
    denoise: [f32; model::DENOISE_NEURONS],
}

impl RnnState {
    pub(crate) fn new() -> Self {
        RnnState {
            vad: [0.0; model::VAD_NEURONS],
            noise: [0.0; model::NOISE_NEURONS],
            denoise: [0.0; model::DENOISE_NEURONS],
        }
    }
}

/// `tansig_approx`: tanh from a 201-entry table and one correction step.
fn tansig(x: f32) -> f32 {
    // The tests run reversed so that a NaN answers 1, as the C's do. (Its
    // NaN check after them never runs.)
    if !(x < 8.0) {
        return 1.0;
    }
    if !(x > -8.0) {
        return -1.0;
    }
    let (mut x, sign) = if x < 0.0 { (-x, -1.0f32) } else { (x, 1.0) };
    let i = f64::from(0.5 + 25.0 * x).floor() as i32;
    x -= 0.04 * i as f32;
    let y = TANSIG_TABLE[i as usize];
    let dy = 1.0 - y * y;
    sign * (y + x * dy * (1.0 - y * x))
}

/// `sigmoid_approx`: ½ + ½·tanh(x/2), the halves in double as the C's
/// literals make them.
fn sigmoid(x: f32) -> f32 {
    let t = tansig((0.5 * f64::from(x)) as f32);
    (0.5 + 0.5 * f64::from(t)) as f32
}

fn relu(x: f32) -> f32 {
    if x < 0.0 { 0.0 } else { x }
}

fn activate(activation: Activation, x: f32) -> f32 {
    match activation {
        Activation::Tanh => tansig(x),
        Activation::Sigmoid => sigmoid(x),
        Activation::Relu => relu(x),
    }
}

/// `compute_dense`.
fn dense(layer: &Dense, output: &mut [f32], input: &[f32]) {
    let n = layer.neurons;
    for (i, out) in output.iter_mut().enumerate().take(n) {
        let mut sum = f32::from(layer.bias[i]);
        for (j, &x) in input.iter().enumerate().take(layer.inputs) {
            sum += f32::from(layer.input_weights[j * n + i]) * x;
        }
        *out = activate(layer.activation, WEIGHTS_SCALE * sum);
    }
}

/// One gate's sum for neuron `i` — `part` 0 the update, 1 the reset, 2
/// the output — over the input and, each weighted by `recur(j)`, the
/// state.
fn gate_sum(gru: &Gru, part: usize, i: usize, input: &[f32], state: &[f32], recur: impl Fn(usize) -> f32) -> f32 {
    let n = gru.neurons;
    let stride = 3 * n;
    let mut sum = f32::from(gru.bias[part * n + i]);
    for (j, &x) in input.iter().enumerate().take(gru.inputs) {
        sum += f32::from(gru.input_weights[part * n + j * stride + i]) * x;
    }
    for (j, &s) in state.iter().enumerate().take(n) {
        sum += f32::from(gru.recurrent_weights[part * n + j * stride + i]) * s * recur(j);
    }
    sum
}

/// `compute_gru`: `state` stepped over `input`.
fn gru(gru: &Gru, state: &mut [f32], input: &[f32]) {
    let n = gru.neurons;
    let mut z = [0.0f32; MAX_NEURONS];
    let mut r = [0.0f32; MAX_NEURONS];
    let mut h = [0.0f32; MAX_NEURONS];
    for i in 0..n {
        z[i] = sigmoid(WEIGHTS_SCALE * gate_sum(gru, 0, i, input, state, |_| 1.0));
    }
    for i in 0..n {
        r[i] = sigmoid(WEIGHTS_SCALE * gate_sum(gru, 1, i, input, state, |_| 1.0));
    }
    for i in 0..n {
        let sum = activate(gru.activation, WEIGHTS_SCALE * gate_sum(gru, 2, i, input, state, |j| r[j]));
        h[i] = z[i] * state[i] + (1.0 - z[i]) * sum;
    }
    state[..n].copy_from_slice(&h[..n]);
}

/// `compute_rnn` without its voice probability: each band's gain for one
/// frame's features.
pub(crate) fn band_gains(rnn: &mut RnnState, input: &[f32; INPUT_SIZE]) -> [f32; GAINS] {
    let mut dense_out = [0.0f32; model::INPUT_DENSE_NEURONS];
    dense(&model::INPUT_DENSE, &mut dense_out, input);
    gru(&model::VAD_GRU, &mut rnn.vad, &dense_out);
    let noise_input = [&dense_out[..], &rnn.vad[..], &input[..]].concat();
    gru(&model::NOISE_GRU, &mut rnn.noise, &noise_input);
    let denoise_input = [&rnn.vad[..], &rnn.noise[..], &input[..]].concat();
    gru(&model::DENOISE_GRU, &mut rnn.denoise, &denoise_input);
    let mut gains = [0.0f32; GAINS];
    dense(&model::DENOISE_OUTPUT, &mut gains, &rnn.denoise);
    gains
}
