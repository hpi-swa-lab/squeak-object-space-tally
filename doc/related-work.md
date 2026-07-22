# SWA -- Related Work

[motivation](motivation) | [ideas](ideas.md) | [architecture](architecture.md)

![](_navigation.html)

## Software Cartography / Code-as-Terrain

- **Codemap / Software Cartography** (Kuhn, Loretan, Nierstrasz -- Bern) -- spatial map
  with a stable coordinate system; concerns (search, bugs, authors) project onto it.
- **CodeCity** (Wettel, Lanza -- Lugano) -- classes as buildings, packages as
  districts, metrics as height/colour. 3D antecedent of our size=metric/colour=metric.
- **Software maps** (Bohnet, Döllner) and the **HPI** line (Limberger, Scheibel, Trapp,
  Döllner) -- treemap-based, multi-metric, evolution-aware maps; attribute layering;
  level-of-detail. 

## Treemap-based Software Visualization

- **Treemaps** (Shneiderman)
- **Squarified treemaps** (Bruls, Huijsen, van Wijk) 
  (`squarify:scales:into:`).

## Software Visualization Frameworks in Smalltalk

- **Moose** (Nierstrasz, Ducasse) -- model-driven analysis on the **FAMIX** meta-model;
  Pharo; language-agnostic. Broader and model-first.
- **Roassal** -- Pharo visualization engine Moose renders through; bind size/colour/edges
  to a domain.
- **Glamorous Toolkit** (feenk) -- moldable development; live per-object custom views.

## Discussion

- **In-image:** runs inside the running Squeak image it inspects (not Pharo/batch).
- **Live instrumentation substrate:** `SWAMethodWrapper` / `SWACapturingLayer` feed
  coverage and call tallies from the same UI that draws them.
- **In-place tool morphing:** the Tree button swaps the base structure; both views cached.
- **Dataset algebra (the claim):** analysis results are composable, retained,
  `crossRefKey`-keyed datasets with *operations* -- Moose/Roassal overlay/bind metrics
  but do not subtract, mask, and re-project as a closing operation.

## Dataset Algebra

- **project** -- read any open view live as a `#peer` dataset; colour/size/structure
  another view by it (`SWAPeerViewSource`).
- **mask / subtract** -- set arithmetic over two datasets (`SWAMaskSource`, `B \ A`
  today; meant to close to union / intersection / xor); the mask inherits B's metrics
  gated to the survivor set, not a boolean hit.
- **decorate vs structure** -- any dataset either colours an existing tree or *becomes*
  the tree (`SWAStructure`).

