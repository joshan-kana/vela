import { NativeModules } from 'react-native';

import {
  deleteAccount,
  listAccounts,
  savePermanentTokenAccount,
  withConnection,
  type StoredAccount,
} from '../src/native/AccountStore';

const account: StoredAccount = {
  id: 'account-1',
  service_url: 'https://example.youtrack.cloud',
  auth_kind: 'permanent_token',
};

const mockStore = {
  listAccounts: jest.fn(),
  savePermanentTokenAccount: jest.fn(),
  deleteAccount: jest.fn(),
  loadAccountToken: jest.fn(),
};

beforeEach(() => {
  jest.clearAllMocks();
  NativeModules.VelaRust = mockStore;
});

test('stores permanent-token accounts through the native secure store', async () => {
  mockStore.savePermanentTokenAccount.mockResolvedValue(account);

  await expect(
    savePermanentTokenAccount(
      ' https://example.youtrack.cloud ',
      ' perm:token ',
    ),
  ).resolves.toEqual(account);

  expect(mockStore.savePermanentTokenAccount).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    'perm:token',
  );
});

test('lists and deletes stored accounts through the native secure store', async () => {
  mockStore.listAccounts.mockResolvedValue([account]);
  mockStore.deleteAccount.mockResolvedValue(undefined);

  await expect(listAccounts()).resolves.toEqual([account]);
  await expect(deleteAccount(account.id)).resolves.toBeUndefined();
});

test('resolves stored credentials only for the duration of an operation', async () => {
  mockStore.loadAccountToken.mockResolvedValue('perm:secret');
  const operation = jest.fn().mockResolvedValue('ok');

  await expect(
    withConnection(
      {
        service_url: account.service_url,
        account_id: account.id,
      },
      operation,
    ),
  ).resolves.toBe('ok');

  expect(mockStore.loadAccountToken).toHaveBeenCalledWith(account.id);
  expect(operation).toHaveBeenCalledWith(account.service_url, 'perm:secret');
});

test('guest connections do not access secure storage', async () => {
  const operation = jest.fn().mockResolvedValue('guest');

  await expect(
    withConnection(
      {
        service_url: account.service_url,
        account_id: null,
      },
      operation,
    ),
  ).resolves.toBe('guest');

  expect(mockStore.loadAccountToken).not.toHaveBeenCalled();
  expect(operation).toHaveBeenCalledWith(account.service_url, '');
});
