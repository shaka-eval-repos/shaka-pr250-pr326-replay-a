# Verify documentation changes

Correct links, rendered pages, and passing code tests catch mechanical problems.
They do not show that someone can find an answer, understand it, or act correctly.
Line counts and token budgets constrain size; they do not establish usefulness.

Before a substantial rewrite, name the audience and a few tasks the document must
support. Map important removed instructions to their new destination, or explain why
they are no longer needed. Preserve direct routes to common tasks and existing anchors.
A shorter page that hides an essential answer is a regression.

Use separate entry points for people and agents, with one maintained source for each
rule. Human guides explain the goal, choices, examples, and recovery. The agent skill
specifies execution order, required references, authority, and stopping conditions;
Fixed `.agents/bin/` scripts supply repository-specific commands, while `AGENTS.md`
supplies human-only constraints and repository context. An agent can also be a
reader of a human guide, so test that use when it is part of the product.

| Reader and task | Useful evidence |
| --- | --- |
| A person wants to control merging | Starting at the README, finds the merge choice and explains what Ask and Auto authorize, including required approvals. |
| A person wants to install and complete a first task | Follows the guide in a fresh session through a PR; record missing steps, wrong turns, questions, and corrections. |
| A maintainer needs help with review, usage, or upgrades | Finds the named guide from the entry page without knowing filenames or searching the repository. |
| An agent follows the procedure | In an isolated trial, takes the correct actions for a bounded task: preserves review-only scope, points an Ask-ready PR at GitHub merge, and respects Auto's required gates. |
| An agent consumes a rewritten guide | Completes the same representative task with the old and new guide; compare omitted requirements, incorrect actions, interventions, and available usage. |

Give a trial reader the document's normal entry point and task, without extra hints
from its author. Observe what they do and ask them to explain their next action.
An author's walkthrough or another model's prose review can find defects, but is not
a substitute for an observed fresh-reader result. An agent trial does not prove human
readability; a human review does not prove agent execution. Label each kind of evidence.
Use a human trial when making a human-usability claim and an agent trial when changing
execution instructions. Repeat ambiguous agent results before claiming reliability.

Match the effort to the change. A typo or repaired link needs a focused check; a
reorganization needs task-based navigation review; changed procedural instructions
need relevant behavior trials. For comparisons, hold the task, starting state, and
agent model/settings constant where possible. Report the tested revision, reader type,
result, corrections, and evidence gaps on the existing PR. Treat token savings as
secondary to correct task completion and human attention. Do not add wording tests
or infer success from the document's length.
