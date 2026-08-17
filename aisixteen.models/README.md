# aisixteen.models — shared

On-device image models, shared by the three AISixteen apps:

| App | Bundle ID | Apple ID |
|---|---|---|
| AISixteen Wallpapers | `oleksandr.aisixteen.wallpapers` | 1662226479 |
| AISixteen Studio | `oleksandr.aisixteen.studio` | 1659835815 |
| AISixteen Architecture | `oleksandr.aisixteen.architecture` | 6475354624 |

**This is a shared folder. Never fork it into an app directory.** Same rule as `marketing/` — a copy
silently stops receiving fixes.

Each app ships its model as an **Apple-hosted Background Assets asset pack**, so the weights are
never committed here and never end up in a build. What lives in this folder is the conversion and
packaging work: the scripts that turn an upstream checkpoint into a Core ML / MLX artefact, the
asset-pack manifests, and the record of which model version an app is on.

Model artefacts (`*.mlpackage`, `*.mlmodelc`, `*.safetensors`, packed `.aar`) are **build outputs and
stay out of git.**
