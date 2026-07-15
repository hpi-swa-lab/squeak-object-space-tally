# Squeak ObjectSpaceTally

[docs](doc/SWASpaceTally.md) 

Structural memory analysis for Squeak. Instead of a flat per-class table
like the built-in `SpaceTally`, this walks the live object graph from the
roots and builds a tree of space usage you can explore three ways:

- **Explorer**, a multi-column tree browser with Tally / Treemap / Diff actions
- **Treemap**, a squarified treemap where area = byte size, with zoom and tooltips
- **Diff**, compares two tallies to isolate exactly what your app allocated

The treemap shares a common view (`SWAView`) and nav panel (`SWANavPanel`) with
its sibling tools -- the **st-spy** message-tally profiler and the static **Code
Map** -- so any two open panels can be **cross-referenced**: e.g. colour the Code
Map by measured memory, or highlight which methods the profiler sampled. See the
[docs](doc/SWASpaceTally.md#cross-referencing-the-views).


![](squeak-object-space-tally.png)

## Installation

To load this package:

```smalltalk
Metacello new
    baseline: 'ObjectSpaceTally';
    repository: 'github://hpi-swa-lab/squeak-object-space-tally:main/src';
    load.
```

To develop this package, use GitS. 

## Quick Start

```smalltalk
spaceTally := SWASpaceTally new
		trackOtherParents: true;
		walk;
		compact:100000.

spaceTally openExplorer.
spaceTally openTreemap.
```

Or from the world menu: **open... -> Space Tally** (or **Code Map** for the
static package/class/method treemap).


## Authors

* Jens Lincke, Software-Architecture Group, HPI, 2026

## AI Usage

* Created with the help of [SqueakMCP](https://github.com/hpi-swa-lab/squeak-mcp) / OpenCode / Claude Opus

## License

MIT -- see [LICENSE](LICENSE).
