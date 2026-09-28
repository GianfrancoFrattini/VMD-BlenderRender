# VMD-BlenderRender

Plugin de VMD que exporta la escena actual a OBJ y la renderiza con Blender.
Incluye render de imagen, perfiles de materiales Principled BSDF y exportacion
de peliculas MP4.

Nombre visible dentro de VMD: `Blender Render`.

> **GitHub description:** A VMD plugin that exports molecular scenes to Blender
> for high-quality still-image and MP4 trajectory rendering.

## Archivos para subir a GitHub

Subi solamente estos tres archivos en la raiz del repositorio:

```text
render2K.tcl
render2k_english.tcl
README.md
```

- `render2K.tcl`: plugin principal con interfaz en espanol.
- `render2k_english.tcl`: interfaz y mensajes en ingles.
- `README.md`: esta guia.

No subas los archivos generados por un render, como `.obj`, `.mtl`,
`*_blender.py`, carpetas `*_frames`, PNG o MP4.

## Requisitos

- VMD con soporte Tcl/Tk y renderizador `Wavefront`.
- Blender disponible como el comando `blender` en `PATH`.
- Blender 3.6 o superior recomendado. Blender 5.2.2 LTS fue verificado con un
  render headless minimo.
- FFmpeg solo para crear peliculas MP4.

El script es para Linux. Cycles intenta usar OptiX o CUDA en GPUs NVIDIA y usa
CPU si no encuentra una GPU compatible. Eevee es la alternativa rapida.

Comproba Blender antes de abrir VMD:

```bash
blender --version
```

## Instalacion

Clona o descarga el repositorio en una ubicacion fija. Por ejemplo:

```text
$HOME/vmd_plugins/
```

Luego agrega una sola linea a `~/.vmdrc`.

Interfaz en espanol:

```tcl
source [file join $env(HOME) vmd_plugins render2K.tcl]
```

Interfaz en ingles:

```tcl
source [file join $env(HOME) vmd_plugins render2k_english.tcl]
```

No cargues ambos archivos. La version inglesa necesita que `render2K.tcl`
siga en el mismo directorio.

Si VMD no encuentra Blender, agrega su directorio a `PATH` antes del `source`:

```tcl
set env(PATH) "/ruta/al/directorio/de/blender:$env(PATH)"
source [file join $env(HOME) vmd_plugins render2K.tcl]
```

Reinicia VMD y abre el plugin desde:

```text
Extensions -> Rendering -> Blender Render
```

La ventana se puede cerrar y volver a abrir desde ese menu sin reiniciar VMD.

## Uso rapido

1. Carga una molecula en VMD y configura sus representaciones.
2. Abre `Extensions -> Rendering -> Blender Render`.
3. Elige Cycles o Eevee, resolucion, nombre de salida y formato.
4. Ajusta perfiles en la pestana de materiales si lo necesitas.
5. Pulsa `RENDERIZAR IMAGEN` o `RENDER IMAGE`.

Para una pelicula, usa la pestana de pelicula, define el rango de frames y el
nombre del MP4. FFmpeg debe estar instalado para esta opcion.

El plugin genera OBJ, MTL y un script Python de Blender junto al archivo de
salida. Desactiva el auto-render de Blender si quieres revisar ese script antes
de renderizar manualmente:

```bash
blender -b -P nombre_blender.py
```

## Imagenes opcionales para GitHub

No son necesarias para que funcione el plugin, pero mejoran mucho el repositorio.
Si las agregas, crea la carpeta `assets/` y usa estos nombres:

| Archivo sugerido | Que mostrar |
| --- | --- |
| `assets/render2k-interface.png` | Ventana principal de Blender Render abierta en VMD |
| `assets/render2k-materials.png` | Pestana de materiales con los perfiles Blender |
| `assets/render2k-example.png` | Comparacion: vista de VMD y render final de Blender |
| `assets/render2k-movie.png` | Pestana de pelicula o un frame final del MP4 |

Cuando tengas las capturas, puedes agregarlas al README con este formato:

```md
![Render2K interface](assets/render2k-interface.png)
![Render2K example](assets/render2k-example.png)
```
