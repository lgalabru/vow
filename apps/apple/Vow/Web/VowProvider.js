(() => {
  'use strict';
  // Page-visible adapter only. Native code rechecks origin, context and all bytes.
  let account, connectionId;
  const listeners = new Set();
  const hex = bytes => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
  const bytes = value => Uint8Array.from(value.match(/../g) ?? [], x => parseInt(x, 16));
  const call = (method, fields = {}) => window.webkit.messageHandlers.vow.postMessage({method, ...fields});
  const changed = () => listeners.forEach(listener => listener({accounts: account ? [account] : []}));
  const connect = async () => {
    const result = await call('connect');
    connectionId = result.connection_id;
    account = Object.freeze({address: result.account, publicKey: bytes(result.account_hex),
      chains: [result.chain], features: ['solana:signTransaction', 'solana:signAndSendTransaction']});
    changed();
    return {accounts: [account]};
  };
  const capture = async (method, ...inputs) => {
    if (!account) throw new Error('Connect Vow first.');
    if (inputs.length !== 1) throw new Error('This preview accepts one transaction at a time.');
    const input = inputs[0];
    if (!(input.transaction instanceof Uint8Array) || input.transaction.length > 1232)
      throw new Error('Unsupported transaction bytes.');
    if (input.account.address !== account.address || (input.chain && !account.chains.includes(input.chain)))
      throw new Error('Wrong account or chain.');
    // The native review owns this request until Done/Cancel. It will reject the
    // signing promise: this capture preview never returns a fabricated signature.
    return call('capture', {connection_id: connectionId, operation: method, account: account.address, chain: input.chain ?? account.chains[0],
      transaction_hex: hex(input.transaction)});
  };
  const features = Object.freeze({
    'standard:connect': {version: '1.0.0', connect},
    'standard:disconnect': {version: '1.0.0', disconnect: async () => {await call('disconnect'); account = undefined; changed();}},
    'standard:events': {version: '1.0.0', on: (event, listener) => {
      if (event !== 'change') throw new Error('Unsupported event.');
      listeners.add(listener); return () => listeners.delete(listener);
    }},
    'solana:signTransaction': {version: '1.0.0', supportedTransactionVersions: ['legacy', 0], signTransaction: (...inputs) => capture('signTransaction', ...inputs)},
    'solana:signAndSendTransaction': {version: '1.0.0', supportedTransactionVersions: ['legacy', 0], signAndSendTransaction: (...inputs) => capture('signAndSendTransaction', ...inputs)}
  });
  const wallet = Object.freeze({version: '1.0.0', name: 'Vow Preview',
    icon: 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA2NCA2NCI+PHJlY3Qgd2lkdGg9IjY0IiBoZWlnaHQ9IjY0IiByeD0iMTQiIGZpbGw9IiMwMDdhZmYiLz48cGF0aCBkPSJNMTYgMjAgMzIgNDQgNDggMjAiIGZpbGw9Im5vbmUiIHN0cm9rZT0id2hpdGUiIHN0cm9rZS13aWR0aD0iNiIvPjwvc3ZnPg==',
    chains: ['solana:devnet', 'solana:mainnet'], get accounts() {return account ? [account] : [];}, features});
  const register = ({register}) => register(wallet);
  class RegisterWalletEvent extends Event {
    constructor() {super('wallet-standard:register-wallet', {bubbles: false, cancelable: false, composed: false});}
    get detail() {return register;}
  }
  window.dispatchEvent(new RegisterWalletEvent());
  window.addEventListener('wallet-standard:app-ready', event => register(event.detail));
})();
