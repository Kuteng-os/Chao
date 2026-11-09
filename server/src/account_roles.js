export const isAdmin = (state, owner) => {
  const key = state.identities[owner]?.account_key;
  return Boolean(key && Object.hasOwn(state.accounts ?? {}, key) && state.accounts[key].role === 'admin');
};
export function audit(state, actor, action, target) {
  state.account_audit ||= [];
  state.account_audit.push({at: new Date().toISOString(), actor, action, target});
  if (state.account_audit.length > 10000) state.account_audit.splice(0, state.account_audit.length - 10000);
}
