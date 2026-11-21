## What's new in this version

## New

- **The Wintab record in the Input Inspector** — on Windows, the steps the app went through as it began taking the pen from Wintab are kept in the Input Inspector (the Debug menu). If the pen stops, that record shows where it stopped.

## Improved

- **Preparing the app on the first launch** — the "Preparing app" window, which had grown longer on a new build's first launch, is back to about its length around November 13. Later launches stay short as before.
- **Memory of imported drawings** — when you import a file such as a .tvpp, each drawing is put down to the session scratch (the disk) as it arrives and lets go of its RAM. The drawings of the frame the canvas stands on stay as they are. With a .tvpp of 220 drawings open, "This app, in RAM" went from 2.26 GB to 0.96 GB (the main PC). In exchange, the import takes about two seconds longer.
- **Memory of an edited cel** — after opening a file, a stroke on a cel of a frame the green band has filled once grows "Drawings" in the memory tab by only the part you drew, not by the whole cel. Cels of the frame that stood when the file was opened are the same as before for now.
- **Saving after many edits** — the app's memory no longer climbs as far while saving after many cels were edited. Saving after editing 220 cels used to climb by 2.0–2.3 GB and now climbs by about 0.64 GB (the main PC).
- **Tile pool** — the drawing engine no longer stores tile memory it let go of to reuse it, and gives it back at once. The "Drawing engine tile pool" row in the memory tab is gone.
- **Fonts** — the graphics engine reads the fonts bundled with the app where they lie instead of keeping a copy. On Windows, "This app, in RAM" fell by about 24 MB. Android is as before.
- **Frame pictures** — once your hand rests, the frame pictures for playback are folded too, using less graphics memory, and the "Frame pictures" row in the memory tab shows the size they really hold. The green band fills further into the room the folding made.
- **The command key of shortcuts** — whatever keyboard is on whatever device, a shortcut's command key does the same whether you press it as Ctrl or as ⌘ (the Win key on a Windows keyboard). There is nothing to set. Ctrl+Z undoes on a Mac too.

## Fixed

- With a viewer open, going to another project tab (an existing tab or one made with Ctrl+N) and coming back kept the page number but showed the first page's picture. Both the main and the sub viewer now come back at the page and zoom they showed.
