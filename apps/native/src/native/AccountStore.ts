import { NativeModules } from 'react-native';

export type StoredAccount = {
  id: string;
  service_url: string;
  auth_kind: 'permanent_token' | 'oauth_pkce';
};

export type OAuthStart = {
  authorization_url: string;
  state: string;
};

export type Connection = {
  service_url: string;
  account_id: string | null;
};

type NativeAccountStore = {
  listAccounts?(): Promise<StoredAccount[]>;
  savePermanentTokenAccount?(
    serviceUrl: string,
    bearerToken: string,
  ): Promise<StoredAccount>;
  deleteAccount?(accountId: string): Promise<void>;
  loadAccountToken?(accountId: string): Promise<string>;
  beginOAuth?(
    serviceUrl: string,
    clientId: string,
    hubUrl: string | null,
    scope: string | null,
  ): Promise<OAuthStart>;
  completeOAuth?(callbackUrl: string): Promise<StoredAccount>;
};

function module(): NativeAccountStore {
  const store = NativeModules.VelaRust as NativeAccountStore | undefined;
  if (!store) {
    throw new Error('Vela account store is unavailable');
  }
  return store;
}

export async function listAccounts(): Promise<StoredAccount[]> {
  const store = module();
  if (!store.listAccounts) {
    throw new Error('Vela account store cannot list accounts');
  }
  return store.listAccounts();
}

export async function savePermanentTokenAccount(
  serviceUrl: string,
  bearerToken: string,
): Promise<StoredAccount> {
  const token = bearerToken.trim();
  if (!token) {
    throw new Error('Permanent token is required');
  }

  const store = module();
  if (!store.savePermanentTokenAccount) {
    throw new Error('Vela account store cannot save accounts');
  }

  return store.savePermanentTokenAccount(serviceUrl.trim(), token);
}

export async function beginOAuth(
  serviceUrl: string,
  clientId: string,
  hubUrl: string | null,
  scope: string | null = null,
): Promise<OAuthStart> {
  const trimmedServiceUrl = serviceUrl.trim();
  const trimmedClientId = clientId.trim();

  if (!trimmedServiceUrl) {
    throw new Error('YouTrack address is required');
  }
  if (!trimmedClientId) {
    throw new Error('OAuth client ID is required');
  }

  const store = module();
  if (!store.beginOAuth) {
    throw new Error('Vela account store cannot start OAuth');
  }

  return store.beginOAuth(
    trimmedServiceUrl,
    trimmedClientId,
    hubUrl?.trim() || null,
    scope?.trim() || null,
  );
}

export async function completeOAuth(
  callbackUrl: string,
): Promise<StoredAccount> {
  const store = module();
  if (!store.completeOAuth) {
    throw new Error('Vela account store cannot complete OAuth');
  }
  return store.completeOAuth(callbackUrl);
}

export async function deleteAccount(accountId: string): Promise<void> {
  const store = module();
  if (!store.deleteAccount) {
    throw new Error('Vela account store cannot delete accounts');
  }
  await store.deleteAccount(accountId);
}

export async function withConnection<T>(
  connection: Connection,
  operation: (serviceUrl: string, bearerToken: string) => Promise<T>,
): Promise<T> {
  if (!connection.account_id) {
    return operation(connection.service_url, '');
  }

  const store = module();
  if (!store.loadAccountToken) {
    throw new Error('Vela account store cannot load credentials');
  }

  const bearerToken = await store.loadAccountToken(connection.account_id);
  return operation(connection.service_url, bearerToken);
}
