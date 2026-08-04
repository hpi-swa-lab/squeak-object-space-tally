# SWA -- Related Work

![](_navigation.html)

## Software Cartography / Code-as-Terrain

- **Codemap / Software Cartography** (Kuhn, Loretan, Nierstrasz)
  - spatial map with a stable coordinate system; concerns (search, bugs, authors) project onto it
- **CodeCity** (Wettel, Lanza) 
  - classes as buildings, packages as districts, metrics as height/colour
- **Software maps** (Bohnet, Döllner) and the **HPI** line (Limberger, Scheibel, Trapp,
  Döllner)
  - treemap-based, multi-metric, evolution-aware maps; attribute layering
  - level-of-detail 

## Treemap-based Software Visualization

- **Treemaps** (Shneiderman)
- **Squarified treemaps** (Bruls, Huijsen, van Wijk) 
 - `squarify:scales:into:`

## Software Visualization Frameworks in Smalltalk

- **Moose** (Nierstrasz, Ducasse) -- model-driven analysis on the **FAMIX** meta-model;
  Pharo; language-agnostic. Broader and model-first
- **Roassal** -- Pharo visualization engine Moose renders through; bind size/colour/edges
  to a domain
- **Glamorous Toolkit** (feenk) -- moldable development; live per-object custom views
