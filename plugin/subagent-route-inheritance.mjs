/**
 * Subagent route inheritance — DSH host plugin.
 *
 * Keeps in-process subagent children on their parent's LIVE provider/model/
 * reasoning-effort route instead of the parent's creation-time AgentOptions:
 *
 * 1. A session model switch (`selectModel`) writes only the session-local
 *    selection, which `installModelSelection` applies to the parent's own
 *    requests; `parent.options` is never rewritten, so a child spawned after
 *    the switch used to run on the pre-switch route.
 * 2. `resolveChildAgentOptions` copies only provider/model/maxTokens, so a
 *    child's first request carried no reasoning effort and silently fell back
 *    to the adapter default.
 *
 * The parent's logged `request/header` is refreshed at the start of every
 * step, before any tool call, so it holds the parent's effective route at
 * delegation time. This plugin mirrors that route onto every child request
 * (and prompt-assembly variables) for the child's whole lifetime, so a switch
 * mid-child takes effect at the next request — the same step-boundary
 * semantics the parent's own selection has.
 *
 * An explicit per-child route override (`agentOptions` on the delegation
 * tool) is left untouched. An adapter-defaulted parent effort is not
 * inherited: the child's own adapter re-materializes its default.
 *
 * Install as a row in a dsh profile's cordis.patch.yml (see install.sh /
 * install.ps1):
 *
 *   - insert:
 *       - id: subagent-route-inheritance
 *         name: ./plugins/subagent-route-inheritance.mjs
 */

const name = 'subagent-route-inheritance'
const inject = ['agents']

function apply(ctx) {
  ctx.on('agent/created', ({ agent }) => {
    const parentId = agent.session.header.parentSession
    if (parentId === undefined) return
    const parent = ctx.agents.get(parentId)
    if (parent === undefined) return
    // An explicit per-child route (tool agentOptions override) stays untouched.
    const overridden = (agent.options.provider ?? undefined) !== (parent.options.provider ?? undefined)
      || (agent.options.model ?? undefined) !== (parent.options.model ?? undefined)
    if (overridden) return
    agent.ctx.on('agent/request', async (_payload, next) => {
      const resolved = await next()
      const header = ctx.agents.get(parentId)?.session.requestHeader()
      const live = header?.config
      if (live === undefined) return resolved
      const updated = { ...resolved, provider: live.provider, model: live.model }
      if (live.reasoningEffort === undefined || header.adapterDefaults?.reasoningEffort === true) {
        delete updated.reasoningEffort
      } else {
        updated.reasoningEffort = live.reasoningEffort
      }
      return updated
    })
    agent.ctx.on('system-prompt/assemble', async (_assembly, _context, next) => {
      const assembled = await next()
      const header = ctx.agents.get(parentId)?.session.requestHeader()
      const live = header?.config
      if (live === undefined) return assembled
      return {
        ...assembled,
        variables: {
          ...assembled.variables,
          provider: live.provider,
          model: live.model,
        },
      }
    })
  })
}

export { apply, inject, name }
