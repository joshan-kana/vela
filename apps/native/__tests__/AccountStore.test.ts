import { NativeModules } from 'react-native';

import {
  beginOAuth,
  completeOAuth,
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
  beginOAuth: jest.fn(),
  completeOAuth: jest.fn(),
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

test('starts OAuth through native PKCE storage without exposing the verifier', async () => {
  mockStore.beginOAuth.mockResolvedValue({
    authorization_url:
      'https://example.youtrack.cloud/hub/api/rest/oauth2/auth?...',
    state: 'state-1',
  });

  await expect(
    beginOAuth(
      ' https://example.youtrack.cloud ',
      ' client-id ',
      ' https://hub.example.com ',
      ' service-id ',
    ),
  ).resolves.toEqual({
    authorization_url:
      'https://example.youtrack.cloud/hub/api/rest/oauth2/auth?...',
    state: 'state-1',
  });

  expect(mockStore.beginOAuth).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    'client-id',
    'https://hub.example.com',
    'service-id',
  );
});

test('completes OAuth through the native secure store', async () => {
  const oauthAccount: StoredAccount = {
    ...account,
    auth_kind: 'oauth_pkce',
  };
  mockStore.completeOAuth.mockResolvedValue(oauthAccount);

  await expect(
    completeOAuth('io.github.joshankana.vela:/oauth/callback?code=x&state=y'),
  ).resolves.toEqual(oauthAccount);
});
