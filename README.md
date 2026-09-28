# VMD-BlenderRender

The VMD Blender Render script connects VMD with Blender to produce high-quality renderings of images and movies quickly. It also solves the issue of rendering size in VMD.

Visible name in VMD: `Blender Render`.

> **GitHub description:** A VMD plugin that exports molecular scenes to Blender
> for high-quality still-image and MP4 trajectory rendering.

## Files to Upload to GitHub

Upload only these three files to the repository root:

```text
render2K.tcl
render2k_english.tcl
README.md
```

- `render2K.tcl`: main plugin with the Spanish interface.
- `render2k_english.tcl`: English interface and messages.
- `README.md`: this guide.

Do not upload render-generated files such as `.obj`, `.mtl`, `*_blender.py`,
`*_frames` directories, PNG files, or MP4 files.

## Requirements

- VMD with Tcl/Tk support and the `Wavefront` renderer.
- Blender available as the `blender` command in `PATH`.
- Blender 3.6 or newer is recommended. Blender 5.2.2 LTS was verified with a
  minimal headless render.
- FFmpeg is required only for MP4 movie rendering.

The script targets Linux. Cycles tries OptiX or CUDA on NVIDIA GPUs and falls
back to CPU rendering when no compatible GPU is available. Eevee is the faster
alternative.

Check Blender before starting VMD:

```bash
blender --version
```

## Installation

Clone or download the repository to a permanent location, for example:

```text
$HOME/vmd_plugins/
```

Add one line to `~/.vmdrc`.

Spanish interface:

```tcl
source [file join $env(HOME) vmd_plugins render2K.tcl]
```

English interface:

```tcl
source [file join $env(HOME) vmd_plugins render2k_english.tcl]
```

Do not load both files. The English version requires `render2K.tcl` to remain
in the same directory.

If VMD cannot find Blender, add its directory to `PATH` before the `source`
command:

```tcl
set env(PATH) "/path/to/blender-directory:$env(PATH)"
source [file join $env(HOME) vmd_plugins render2K.tcl]
```

Restart VMD and open the plugin from:

```text
Extensions -> Rendering -> Blender Render
```

The window can be closed and reopened from this menu without restarting VMD.

## Quick Use

1. Load a molecule in VMD and configure its representations.
2. Open `Extensions -> Rendering -> Blender Render`.
3. Select Cycles or Eevee, resolution, output name, and format.
4. Adjust material profiles if needed.
5. Click `RENDERIZAR IMAGEN` or `RENDER IMAGE`.

For a movie, use the movie tab, define the frame range, and enter the MP4 name.
FFmpeg must be installed for this option.

The plugin generates OBJ, MTL, and Blender Python files next to the output.
Disable Blender auto-render when you want to inspect the script before rendering
it manually:

```bash
blender -b -P output_blender.py
```

## Optional GitHub Images

Images are not required for the plugin to work, but they improve the repository.
If you add them, create an `assets/` directory and use these suggested names:

| Suggested file | What to show |
| --- | --- |
| `assets/render2k-interface.png` | Blender Render main window open in VMD |
| `assets/render2k-materials.png` | Material tab with Blender profiles |
| `assets/render2k-example.png` | Comparison between the VMD view and the final Blender render |
| `assets/render2k-movie.png` | Movie tab or a final MP4 frame |

After adding the screenshots, include them in the README like this:

```md
![Blender Render interface](assets/render2k-interface.png)
![Blender Render example](assets/render2k-example.png)
```
