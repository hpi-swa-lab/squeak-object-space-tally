# SWA -- Motivation & Perspective

![](_navigation.html)


## What this currently is

- A **finger exercise in agentic programming** ("Fingerübung"): a suite built largely
  by an AI agent, in a live Squeak image, to see how far that mode of work carries.
- A **probe**, built fast, to *ask* a question -- not an evaluated tool. Treat every
  "SWAMaps lets you..." as a hypothesis.
- Deliberately borrowing state-of-the-art rendering ([related-work.md](related-work.md));
  the novelty we chase is narrow (the algebra + live-image + AI-authorship framing) and
  may not pan out.

## What the views are for: curiosity, not detection

These are not analysers that find defects and propose fixes. A treemap does not
know that a tile is wrong. What it does is make one tile large, or red, or oddly
placed, so that somebody asks *why is that like that* — and an endless scrolling
transcript of changes never provokes that question, because a sequence read
linearly has no shape.

The consequence runs through the rest of this documentation. It is why
**reduction** matters more than coverage ([views.md §3.2](views.md#32-reduce)):
an anomaly is only visible against something suppressed, and a floodlit view
provokes nothing. It is why the [findings](stories.md) are worth recording
individually — each is a question that got asked, not an answer a tool produced.
And it is the honest reading of the FFI-boundary result below: the tools
identified nothing, they made something conspicuous enough to investigate.

## Two applications

The suite is pointed at two quite different problems, and they draw on opposite
halves of it.

**Staying oriented in agent-authored code.** The original motivation, below.
Served by the code, history and structure views — which
[views.md §5](views.md#5-the-illumination-map) shows to be the *thinly* covered
half, and which is blocked on the coupling and type measurements that do not yet
exist.

**Making SqueakXR and SWAGame run smoothly on the Quest.** Served by the memory
and execution views — the *heavily* covered half, five instruments deep. This is
where the concrete results are: frame-boundary collection, the survivor hunt, and
the FFI-boundary conversions in [stories.md](stories.md) that now stand between
the application and a smooth frame rate on the headset. Much more work remains,
but the instruments for it exist and are mature.

That asymmetry explains a lot about the project's shape. The performance
application has produced findings because it uses the well-lit half; the
orientation application is still mostly a hypothesis because its half is dark.

## The problem it addresses

- **AI agents now write code far faster than a human can read it.** When the author is
  an agent -- not me, not a colleague -- the incidental context normally built *by
  writing* is gone.
- The bottleneck shifts from "understand my slowly-grown system" to "stay oriented in
  code produced at agent speed": trust it, review it, know where to look.
- So the tool reframes from **cartography** to **coping mechanism**: less "a beautiful
  map of the system", more "an agent changed 40 methods in two minutes -- show me the
  shape of that, where it lands, and what is now different from five minutes ago."

## The suite is its own first case

The recursion is not a curiosity, it is the closest thing to evidence this project
has. SWA was itself written largely by an agent, at agent speed, and is now
**147 classes and 2,608 selectors** that nobody read line by line as they appeared.
It is simultaneously the instrument for coping with agent-authored code, an
instance of agent-authored code, and the first codebase the instrument was pointed
at. Parts of SqueakXR are in the same position, which is the case that actually
matters for colleagues.

So the question is not rhetorical: **can these tools keep their own author
oriented in what the agent wrote?** The first pass is recorded in
[smells.md §9](smells.md) and the result is mixed in an informative way.

*What worked.* An unsent-selector scan over the suite independently confirmed two
dead clusters that had previously been found only by hand, out of 242 non-test
candidates. Running the duplication detector on its own packages worked and found
verbatim pairs.

*What did not.* Three failures, and they are the useful part:

- The duplication detector is scoped to a single package, and **every** duplication
  in the hand audit is cross-package. The tool built to find copy-paste is
  structurally incapable of finding its author's copy-paste.
- "Never sent" cannot distinguish a corpse from an entry point in a live image,
  because the entire workspace-facing API is never sent. Without a marking
  convention the scan produces a list that must be read by hand, which is the work
  it was meant to remove.
- Neither scan reaches the category that actually characterises mud.

## Mud is a coupling phenomenon, and coupling is the dark region

The structural findings in the hand audit — god objects (`SWAPane` at 43 ivars
and ~130 methods), duck-typed protocols between pane and view, datasets that know
their own view classes, two parallel mechanisms for resolving size up the parent
chain — are the classic early indicators. Not a big ball of mud yet, but every
warning sign is present and written down.

None of them shows up in anything the suite currently draws. Size, churn,
coverage, duplication and topic are all **proxies**. What would make coupling
conspicuous is a picture of *who depends on whom*, and that is precisely the dark
region in [views.md §6](views.md#6-dark-spots): no call graph, no fan-in or
fan-out, no package dependency map.

Not because such a view would pronounce a verdict — per the section above, it
would not. Because a cycle, a god object or a layering violation drawn as a shape
is something a person becomes curious about, and the same fact spread across
2,600 selectors is something nobody ever asks about. That is the whole
difference, and it reprioritises [todo.md](todo.md) items 6 and 7 from "an
interesting gap" to the thing that decides whether the orientation application
can be tried at all.

## Whose problem this is

- A **programming-experience** and **live / explorative-programming** question, not a
  rendering one.
- Interesting to us as **Software Architecture / Programming Experience / Explorative &
  Live Programming** researchers precisely because the analysis loop is live and
  in-image rather than a batch report.

## Honest caveats

- Unevaluated. Whether composable live maps help a human cope with AI-authored code is
  an open empirical question, not a claim.
- Real debt exists ([smells.md](smells.md)); several hoped-for directions lean on parts
  (mask algebra, provenance) that are stubbed or unbuilt.
- **Self-application is the weakest form of evaluation.** n = 1, and the author of
  the tool, the author of the codebase and the evaluator are the same party. What
  section 3 reports is suggestive and diagnostic — it found real gaps in the tools
  — but it is not evidence that the tools help anyone else. SqueakXR is the better
  case precisely because its readers are colleagues who did not write it.

## Where this is going

One direction is specific enough to have its own file: SqueakXR is currently the
*target* of these tools, and [vision.md](vision.md) argues for also making it the
*host* — the views running as objects in an XR world, with software-architecture
exploration as a second example domain beside games.
