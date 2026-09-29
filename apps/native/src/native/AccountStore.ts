import { NativeModules } from 'react-native';

export type StoredAccount = {
  id: string;
  service_url: string;
  auth_kind: 'permanent_token';
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
