# Account integration credits

The Claude/Codex installer and statusline changes integrate AgentUsage's owned
account service. Their predecessor stack included
[claude-swap](https://github.com/realiti4/claude-swap) (Onur Cetinkol and
contributors, MIT), our [claude-swap integration fork](https://github.com/possibilities/claude-swap),
[codex-swap](https://github.com/possibilities/codex-swap) (Mike Bannister, MIT),
and its [codex-multi-auth](https://github.com/ndycode/codex-multi-auth) backend
(ndycode and contributors, MIT).

The replacement installer ordering, observer configuration and statusline
integration are maintained in AgentStart. Account/protocol adaptations live
in AgentUsage; its [source credits and upstream license notices](https://github.com/possibilities/agentusage/blob/main/THIRD_PARTY_NOTICES.md)
record their authors, exact reviewed sources and relationship to OpenAI Codex.
Retiring an installation dependency does not remove that credit.

This note covers the account replacement, not the separately distributed tools
and skill packs installed by AgentStart. Those retain their own licenses and
notices. Original AgentStart work is covered by [LICENSE](LICENSE).
