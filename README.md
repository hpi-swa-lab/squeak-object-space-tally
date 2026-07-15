# SWA Code Maps

*(repository still named `squeak-object-space-tally` -- it grew from that one tool
into a suite.)*

**[Gallery](doc/gallery.md)** &middot; **[Docs index](doc/index.md)** &middot;
**[Package overview](doc/packages.md)**

A suite of structural-analysis tools for Squeak. Each visualises a tree of
`SWANode`s through one shared view/chrome/dataset layer (`SWAView` / `SWAPane` /
`SWADataset`) as a navigable squarified treemap, flamegraph, or diagram -- and any
tool can colour itself by another's data, because they all speak the same
`crossRefKey` vocabulary (class names are unique; methods are `'Class>>selector'`).

| Tool | Question it answers |
|---|---|
| **[Code Map](doc/SWACodeMap.md)** | What is the *shape* of this code -- size, docs, coverage, churn? |
| **[Space Tally](doc/SWASpaceTally.md)** | Where does the *memory* go, and who keeps it alive? |
| **[Sampling Tally](doc/SWAMessageTally.md)** | Where does the *time* go at runtime (statistical sampling, via st-spy)? |
| **Change Map** | *When* did the code change, and how much? |
| **Class Diagram** | What is the *inheritance shape* of a package? |

The suite ships as 14 `SWA-*` packages layered on a shared **Base** substrate --
see **[doc/packages.md](doc/packages.md)** for the package map, dependency graph,
and class hierarchy.

![Code Map of SqueakXR, sized by LOC, coloured by kind](doc/gallery-codemap.png)

## The unified data path

Any analysis (coverage, duplication, a space tally, a live profiler sample) can be
loaded onto the Code Map as a **dataset** to colour or size it, and any open panel
can be picked as a live data source from the **Data** menu -- e.g. colour the Code
Map by measured memory, or by which methods the profiler sampled. A space tally
loaded from a node tree can even *become* the Code Map's structure via the
**Tree** button (morph one tool into another). See
[doc/index.md](doc/index.md#datasets-the-unified-data-path).

## Installation

```smalltalk
Metacello new
    baseline: 'ObjectSpaceTally';
    repository: 'github://hpi-swa-lab/squeak-object-space-tally:main/src';
    load.
```

To develop this package, use GitS.

## Quick Start

From the world menu: **open... -> Code Map** (static package/class/method
treemap), or **Space Tally** (live object-memory treemap).

```smalltalk
"Static Code Map of a package"
SWAPane openOnPackageNamed: 'SqueakXR' leafKind: #class.

"Object-memory treemap of the live image"
spaceTally := SWASpaceTally new
    trackOtherParents: true;
    walk;
    compact: 100000.
spaceTally openExplorer.
spaceTally openTreemap.
```

## Authors

* Jens Lincke, Software-Architecture Group, HPI, 2026

## AI Usage

* Created with the help of [SqueakMCP](https://github.com/hpi-swa-lab/squeak-mcp) / OpenCode / Claude Opus

## License

MIT -- see [LICENSE](LICENSE).
