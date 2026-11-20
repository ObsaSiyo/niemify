# niemify design system

Open `design-system.fig` in OpenPencil. The three editable pages cover foundations, native component definitions and variants, and wide/narrow terminal compositions. Import `tokens.css`, then `aliases.css`, then `map.css` when consuming the CSS outside OpenPencil. These are design artifacts; the Lua CLI does not read CSS or ship an interactive GUI.

## Reference decisions

| Source | Observed | Applied |
|---|---|---|
| `.omp/design/niemify-cli-portable.fig` | Dark ink `#101722`, panels `#172231`, dividers `#394b61`, mint `#80e8d0`, amber `#ffbb87`; compact copy and two command panels. | Dark palette, small type roles, grouped panels, mint for confirmation and amber for recovery. Amber is paired with an explicit error label. |
| `bin/niemify`, `README.md` | `help`, `convert`, and `verify`; conversion receipts on stderr, `-` for data-only stdout, and nonzero status for validation or usage errors. | Separate command, result, recovery, and usage specimens; successful and rejected exchange paths. |
| `examples/inventory/` | Valid and invalid synthetic inventory records and an imported SKU schema. | Sample data and schema rejection copy; no real records. |
| No supplied reference for a light mode, non-terminal controls, or narrow layout. | Not observed. | Light theme, reusable controls and form states, and a stacked narrow composition are derived. |

## Component and interaction contract

The component page specifies actions, fields and selection, navigation, layout, overlays, data, and feedback. The terminal compositions are **static design studies** using reusable instances; they do not add interactivity to the CLI. The actual terminal determines its own font and color settings. Keep status understandable via text and exit code without color. For a future visual surface, use labeled controls, visible focus, a 44 px comfortable target where relevant, and reduced-motion equivalents. Dialog concepts imply focus containment and return; they are not wired prototypes.

The `.fig` uses native variable references for compatible color and spacing/shape roles. CSS-only expressions, layout-query thresholds, and actual motion behavior remain in the CSS/specification; OpenPencil previews do not execute them. The core component set is a project design library, not a one-to-one port of every shadcn registry entry.

## Verification

Reopened the `.fig` and verified 30 component definitions or families represented by 52 main components and 19 variant sets, 18 linked instances, 364 layers with variable bindings, and a real light-mode override on the narrow composition. The three boards rendered with strict font checking. Chrome resolved the CSS layers and passed 24 selected light/dark text, status, input and focus contrast checks.

Previews: [Foundations](foundations.png), [Components](components.png), and [Patterns](patterns.png).
