# Manager model-routing sources and limits

Verified September 14, 2026. This is the evidence behind the concise guide in
[the manager APPEND](../roles/manager/APPEND_SYSTEM_PROMPT.md), not another
runtime configuration or model catalog. [ADR 0016](adr/0016-manager-model-selection-guide.md)
records the operator's decision; the worker prompt is outside this change.

## Selection policy and native support

The human requested Sol extensively for ordinary work, explicitly including
high/xhigh. The human clarified that Astra is appropriate when creativity, design,
design engineering, product engineering, deep thinking or architecture is central,
as well as for large complex workflows. Judgment-heavy design/product work does
not require an exceptionally complex implementation to merit Astra. Routine
implementation retains the approved default child setting of Sol/medium.
The current AgentVoice conversational root is Astra/low; that does not identify
other manager launches or override actual runtime settings.

The active native `collaboration.spawn_agent` description advertises these IDs:

| Native ID | Advertised efforts | Advertised service tier |
| --- | --- | --- |
| `gpt-6-astra` | low, medium, high, xhigh, max, ultra | priority |
| `gpt-5.6-sol` | low, medium, high, xhigh, max, ultra | priority |
| `gpt-5.6-terra` | low, medium, high, xhigh, max, ultra | priority |
| `gpt-5.6-luna` | low, medium, high, xhigh, max | priority |
| `gpt-5.5` | low, medium, high, xhigh | priority |

This is observed tool advertisement, not backend execution proof. In particular,
the public API cards list `none` for some families and omit native `ultra`;
neither changes this tool's controls. Full-history forks inherit model/effort;
reuse does not change them. Fresh or bounded forks can select them where the host
permits it. Consult the live catalog when it differs from this dated evidence.

## Brain retrieval and primary model guidance

The requested Brain search and full retrieval returned these saved sources:

| Brain reference | Source and contribution |
| --- | --- |
| document 1040; discovery chunk 15245; saved 2026-09-07 | [OpenAI model guidance](https://developers.openai.com/api/docs/guides/latest-model): Astra persistence, instruction sensitivity, delegation and proportionate testing. Full 16,633-character body retrieved. |
| document 1024; discovery chunk 15067; saved 2026-09-06 | [Rethinking skills and prompts for GPT-6 Astra](https://x.com/i/status/2095991462416490862): concise instructions, relevant disclosure and explicit completion boundaries. Full 5,756-character body retrieved; contextual commentary, not model availability authority. |
| document 838; discovery chunk 11947; saved 2026-08-07 | [Practical multi-agent orchestration in Codex](https://x.com/i/status/2080707291603407077): Sol medium for scoped work and high for harder work, focused assignments and context boundaries. Full 3,867-character body retrieved; its concurrency/control claims are not imported. |
| document 632, chunk 9803 | [Simon Willison's discussion](https://simonwillison.net/2026/Jul/21/cat-and-thariq/): supplied the exact GPT-5.6 prompting link below. Retrieved as source discovery, not the primary support for the guide. |

Bounded Brain searches for model cards, GPT-5.6, flagship models and Spark quota
did not return the relevant primary cards. Exact Astra and Sol card URI lookups
returned `not_found`. Do not describe the following live reads as retrieved Brain
cards. Their official pages were searched and opened on September 14:

- [Astra card](https://developers.openai.com/api/docs/models/gpt-6-astra): strongest end-to-end model positioning; the creative/design routing boundary is the operator's explicit preference.
- [Sol card](https://developers.openai.com/api/docs/models/gpt-5.6-sol): capable professional-work model; the ordinary-work default is the operator's policy.
- [Terra card](https://developers.openai.com/api/docs/models/gpt-5.6-terra): balances capability and cost; consider total accepted-result cost.
- [Luna card](https://developers.openai.com/api/docs/models/gpt-5.6-luna): designed for economical high-volume work; narrow extraction and transformation are local routing recommendations.
- [GPT-5.5 card](https://developers.openai.com/api/docs/models/gpt-5.5): retained advertised option, without a claim that it should replace the new default.

The freshly opened [GPT-5.6 prompting guide](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-5.6#favor-leaner-prompts)
supports reducing repetition and supplying only relevant tools/context. The
[Astra prompting guide](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices)
supports explicit authorized completion, delegation discretion and bounded
verification. These principles inform the brief advice; they do not justify
copying full prompts, API-specific controls or benchmark claims into the role.

## Subscription observations and Spark

Use AgentUsage, not AgentBalance. Its current installed `guide --json` exposes
one-shot `usage --json` and `status --json` reads. It does not expose a model/effort
catalog. On September 14 at 20:39 UTC, its Codex observation was healthy and
approximately two minutes old, with two Pro account records, each reporting
`measurementSource: current` and `decisionGrade: true`. Both exposed distinct
`main` and `codex-spark` lanes; Spark included finite five-hour and weekly
windows. The status preview reported available Spark headroom without claiming
a lease. Account observations and selection previews alone do not bind this
running thread to a particular account. Keep changing percentages and private
identifiers out of the standing prompt; correlate a current launch through
authoritative runtime evidence before making capacity claims about it.

The human clarified that Spark's quota is separate and finite. Current official
[Codex speed documentation](https://learn.chatgpt.com/docs/agent-configuration/speed#codex-spark)
identifies GPT-5.3-Codex-Spark as a separate fast coding model with its own usage
limits. [Codex pricing](https://learn.chatgpt.com/docs/pricing#what-are-the-usage-limits-for-my-plan)
describes a Pro research preview with a separate limit that may vary with demand.
These sources and AgentUsage support separate metering, not free/unlimited work
or a guaranteed amount of remaining capacity.

Spark is absent from the current native spawn catalog, and this Codex-led role's
existing policy excludes Spark workers. Do not translate an AgentUsage lane into
a callable model, invent Spark reasoning controls, or route around the policy
through another launcher. Its separate quota does not power a non-Spark lead.
The human's desired mechanical-work use is retained as a separate policy and
capability decision; no Spark execution, account switch or credential access
is included in this change.

API prices, subscription meters, configured tier and observed task outcomes
describe different things. The guide makes no account-specific quota-savings
ratio or universal model-quality claim. Validate ordinary outcomes through
existing routing receipts, native configuration and parent acceptance rather
than creating a new benchmark requirement.
