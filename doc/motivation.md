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

## The problem it addresses

- **AI agents now write code far faster than a human can read it.** When the author is
  an agent -- not me, not a colleague -- the incidental context normally built *by
  writing* is gone.
- The bottleneck shifts from "understand my slowly-grown system" to "stay oriented in
  code produced at agent speed": trust it, review it, know where to look.
- So the tool reframes from **cartography** to **coping mechanism**: less "a beautiful
  map of the system", more "an agent changed 40 methods in two minutes -- show me the
  shape of that, where it lands, and what is now different from five minutes ago."

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
