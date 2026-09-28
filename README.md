# VMD-BlenderRender

The VMD Blender Render script connects VMD with Blender to produce high-quality renderings of images and movies quickly. It also solves the issue of rendering size in VMD.

Visible name in VMD: `Blender Render`.

> **GitHub description:** A VMD plugin that exports molecular scenes to Blender
> for high-quality still-image and MP4 trajectory rendering.

## Included Scripts

- `BlenderRender_SP.tcl`: Spanish interface.
- `BlenderRender_EN.tcl`: English interface. It loads `BlenderRender_SP.tcl`,
  so both files must remain in the same directory.

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
source [file join $env(HOME) vmd_plugins BlenderRender_SP.tcl]
```

English interface:

```tcl
source [file join $env(HOME) vmd_plugins BlenderRender_EN.tcl]
```

Do not load both files. The English version requires `BlenderRender_SP.tcl` to remain
in the same directory.

If VMD cannot find Blender, add its directory to `PATH` before the `source`
command:

```tcl
set env(PATH) "/path/to/blender-directory:$env(PATH)"
source [file join $env(HOME) vmd_plugins BlenderRender_SP.tcl]
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

## Optional Screenshots

Images are not required for the plugin to work, but they improve the repository.
If you add them, create an `assets/` directory and use these suggested names:

| Suggested file | What to show |
| --- | --- |
| `assets/blender-render-interface.png` | Blender Render main window open in VMD |
| `assets/blender-render-materials.png` | Material tab with Blender profiles |
| `assets/blender-render-example.png` | Comparison between the VMD view and the final Blender render |
| `assets/blender-render-movie.png` | Movie tab or a final MP4 frame |

After adding the screenshots, include them in the README like this:

```md
![Blender Render interface](assets/blender-render-interface.png)
![Blender Render example](assets/blender-render-example.png)
```
