import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import { Text, TextInput } from 'react-native';

import App from '../App';
import {
  beginOAuth,
  listAccounts,
  savePermanentTokenAccount,
  withConnection,
} from '../src/native/AccountStore';
import {
  discoverYouTrack,
  executeIssueAction,
  loadIssueDetails,
  loadIssueLinks,
  loadMyWork,
  loadCachedMyWork,
  refreshMyWork,
  persistMyWork,
  loadProjectSchema,
} from '../src/native/VelaRust';

jest.mock('../src/native/AccountStore', () => ({
  beginOAuth: jest.fn(),
  completeOAuth: jest.fn(),
  deleteAccount: jest.fn(),
  listAccounts: jest.fn(),
  savePermanentTokenAccount: jest.fn(),
  withConnection: jest.fn(),
}));

jest.mock('../src/native/VelaRust', () => ({
  applyCustomFieldEvent: jest.fn(),
  discoverYouTrack: jest.fn(),
  executeIssueAction: jest.fn(),
  loadIssueDetails: jest.fn(),
  loadIssueLinks: jest.fn(),
  loadMyWork: jest.fn(),
  loadCachedMyWork: jest.fn(),
  refreshMyWork: jest.fn(),
  persistMyWork: jest.fn(),
  loadProjectSchema: jest.fn(),
  setCustomFieldValue: jest.fn(),
  setIssueDescription: jest.fn(),
  setIssueSummary: jest.fn(),
}));

const mockBeginOAuth = jest.mocked(beginOAuth);
const mockListAccounts = jest.mocked(listAccounts);
const mockSavePermanentTokenAccount = jest.mocked(savePermanentTokenAccount);
const mockWithConnection = jest.mocked(withConnection);
const mockDiscoverYouTrack = jest.mocked(discoverYouTrack);
const mockExecuteIssueAction = jest.mocked(executeIssueAction);
const mockLoadMyWork = jest.mocked(loadMyWork);
const mockLoadCachedMyWork = jest.mocked(loadCachedMyWork);
const mockRefreshMyWork = jest.mocked(refreshMyWork);
const mockPersistMyWork = jest.mocked(persistMyWork);
const mockLoadIssueDetails = jest.mocked(loadIssueDetails);
const mockLoadIssueLinks = jest.mocked(loadIssueLinks);
const mockLoadProjectSchema = jest.mocked(loadProjectSchema);

beforeEach(() => {
  jest.clearAllMocks();
  mockListAccounts.mockResolvedValue([]);
  mockLoadCachedMyWork.mockResolvedValue(null);
  mockPersistMyWork.mockResolvedValue(undefined);
  mockRefreshMyWork.mockImplementation((url, token) =>
    mockLoadMyWork(url, token),
  );
  mockWithConnection.mockImplementation(async (connection, operation) =>
    operation(
      connection.service_url,
      connection.account_id ? 'stored-token' : '',
    ),
  );
});

test('renders the YouTrack connection form', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  const text = renderer!.root
    .findAllByType(Text)
    .map(node => node.props.children);

  expect(text).toContain('My Work');
  expect(text).toContain('Connect to YouTrack');
  expect(renderer!.root.findAllByType(TextInput)).toHaveLength(5);
});

test('renders issues returned by the Rust bridge', async () => {
  mockLoadMyWork.mockResolvedValueOnce({
    user: {
      id: '1-1',
      login: 'joshan',
      full_name: 'Joshan',
      email: null,
      guest: false,
    },
    issues: [
      {
        id: '2-1',
        id_readable: 'VELA-1',
        summary: 'Build the first real issue list',
        resolved_at: null,
      },
    ],
  });

  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  const address = renderer!.root.findAllByType(TextInput)[0];

  await ReactTestRenderer.act(() => {
    address.props.onChangeText('https://example.youtrack.cloud');
  });

  const connect = renderer!.root.findByProps({
    accessibilityLabel: 'Connect with token or guest access',
  });

  await ReactTestRenderer.act(async () => {
    await connect.props.onPress();
  });

  const text = renderer!.root
    .findAllByType(Text)
    .flatMap(node =>
      Array.isArray(node.props.children)
        ? node.props.children
        : [node.props.children],
    );

  expect(mockLoadMyWork).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
  );
  expect(text).toContain('VELA-1');
  expect(text).toContain('Build the first real issue list');
});

test('stores a permanent-token account after a successful connection', async () => {
  mockLoadMyWork.mockResolvedValueOnce({
    user: {
      id: '1-1',
      login: 'joshan',
      full_name: 'Joshan',
      email: null,
      guest: false,
    },
    issues: [],
  });
  mockSavePermanentTokenAccount.mockResolvedValueOnce({
    id: 'account-1',
    service_url: 'https://example.youtrack.cloud',
    auth_kind: 'permanent_token',
  });

  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  const address = renderer!.root.findByProps({
    accessibilityLabel: 'YouTrack address',
  });
  const token = renderer!.root.findByProps({
    accessibilityLabel: 'Permanent token',
  });
  await ReactTestRenderer.act(() => {
    address.props.onChangeText('https://example.youtrack.cloud');
    token.props.onChangeText('perm:secret');
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({
        accessibilityLabel: 'Connect with token or guest access',
      })
      .props.onPress();
  });

  expect(mockLoadMyWork).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    'perm:secret',
  );
  expect(mockSavePermanentTokenAccount).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    'perm:secret',
  );
});

test('starts OAuth with a preregistered public client', async () => {
  mockBeginOAuth.mockResolvedValueOnce({
    authorization_url:
      'https://example.youtrack.cloud/hub/api/rest/oauth2/auth?client_id=client-id',
    state: 'state-1',
  });

  const openUrl = jest
    .spyOn(require('react-native').Linking, 'openURL')
    .mockResolvedValueOnce(undefined);

  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  const address = renderer!.root.findByProps({
    accessibilityLabel: 'YouTrack address',
  });
  const clientId = renderer!.root.findByProps({
    accessibilityLabel: 'OAuth client ID',
  });

  await ReactTestRenderer.act(() => {
    address.props.onChangeText('https://example.youtrack.cloud');
    clientId.props.onChangeText('client-id');
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({ accessibilityLabel: 'Connect with OAuth' })
      .props.onPress();
  });

  expect(mockBeginOAuth).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    'client-id',
    null,
    null,
  );
  expect(openUrl).toHaveBeenCalledWith(
    'https://example.youtrack.cloud/hub/api/rest/oauth2/auth?client_id=client-id',
  );

  openUrl.mockRestore();
});

test('reconnects a saved account without putting its token in UI state', async () => {
  mockListAccounts.mockResolvedValueOnce([
    {
      id: 'account-1',
      service_url: 'https://saved.youtrack.cloud',
      auth_kind: 'permanent_token',
    },
  ]);
  mockLoadMyWork.mockResolvedValueOnce({
    user: {
      id: '1-1',
      login: 'joshan',
      full_name: 'Joshan',
      email: null,
      guest: false,
    },
    issues: [],
  });

  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({
        accessibilityLabel: 'Connect https://saved.youtrack.cloud',
      })
      .props.onPress();
  });

  expect(mockWithConnection).toHaveBeenCalledWith(
    {
      service_url: 'https://saved.youtrack.cloud',
      account_id: 'account-1',
    },
    expect.any(Function),
  );
  expect(mockRefreshMyWork).toHaveBeenCalledWith(
    'https://saved.youtrack.cloud',
    'stored-token',
    'account-1',
  );
});

test('creates an issue through the shared action layer and opens it', async () => {
  mockLoadMyWork.mockResolvedValueOnce({
    user: {
      id: '1-1',
      login: 'joshan',
      full_name: 'Joshan',
      email: null,
      guest: false,
    },
    issues: [],
  });
  mockDiscoverYouTrack.mockResolvedValueOnce({
    projects: {
      capability: 'available',
      items: [
        {
          id: '0-7',
          short_name: 'vela',
          name: 'Vela',
          archived: false,
        },
      ],
    },
    users: 'available',
    issue_link_types: { capability: 'available', items: [] },
    agile_boards: 'available',
    saved_queries: 'available',
  });

  const created = {
    id: '2-5',
    id_readable: 'vela-5',
    summary: 'Add quick creation',
    description: 'Created from Vela',
    created_at: 1780000000000,
    updated_at: 1780000000000,
    resolved_at: null,
    project: {
      id: '0-7',
      short_name: 'vela',
      name: 'Vela',
      archived: false,
    },
    custom_fields: [],
  };
  mockExecuteIssueAction.mockResolvedValueOnce({
    kind: 'issue',
    issue: created,
  });
  mockLoadIssueDetails.mockResolvedValueOnce(created);
  mockLoadProjectSchema.mockResolvedValueOnce({
    project: created.project,
    custom_fields: [],
  });
  mockLoadIssueLinks.mockResolvedValueOnce([]);

  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  await ReactTestRenderer.act(() => {
    renderer!.root
      .findByProps({ accessibilityLabel: 'YouTrack address' })
      .props.onChangeText('https://example.youtrack.cloud');
  });
  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({
        accessibilityLabel: 'Connect with token or guest access',
      })
      .props.onPress();
  });

  await ReactTestRenderer.act(async () => {
    renderer!.root
      .findByProps({ accessibilityLabel: 'New issue' })
      .props.onPress();
    await Promise.resolve();
  });

  await ReactTestRenderer.act(() => {
    renderer!.root
      .findByProps({ accessibilityLabel: 'New issue summary' })
      .props.onChangeText('Add quick creation');
    renderer!.root
      .findByProps({ accessibilityLabel: 'New issue description' })
      .props.onChangeText('Created from Vela');
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({ accessibilityLabel: 'Create issue' })
      .props.onPress();
  });

  expect(mockDiscoverYouTrack).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
  );
  expect(mockExecuteIssueAction).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    {
      kind: 'create_issue',
      project_id: '0-7',
      summary: 'Add quick creation',
      description: 'Created from Vela',
    },
  );
  expect(mockLoadIssueDetails).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    '2-5',
  );
});

test('opens the issue inspector with schema and links', async () => {
  mockLoadMyWork.mockResolvedValueOnce({
    user: {
      id: '1-1',
      login: 'joshan',
      full_name: 'Joshan',
      email: null,
      guest: false,
    },
    issues: [
      {
        id: '2-4',
        id_readable: 'vela-4',
        summary: 'Build issue inspector and generic field editing',
        resolved_at: null,
      },
    ],
  });
  mockLoadIssueDetails.mockResolvedValueOnce({
    id: '2-4',
    id_readable: 'vela-4',
    summary: 'Build issue inspector and generic field editing',
    description: 'Inspector scope',
    created_at: 1780000000000,
    updated_at: 1780001000000,
    resolved_at: null,
    project: {
      id: '0-7',
      short_name: 'vela',
      name: 'Vela',
      archived: false,
    },
    custom_fields: [],
  });
  mockLoadProjectSchema.mockResolvedValueOnce({
    project: {
      id: '0-7',
      short_name: 'vela',
      name: 'Vela',
      archived: false,
    },
    custom_fields: [],
  });
  mockLoadIssueLinks.mockResolvedValueOnce([]);

  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  const address = renderer!.root.findAllByType(TextInput)[0];
  await ReactTestRenderer.act(() => {
    address.props.onChangeText('https://example.youtrack.cloud');
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({
        accessibilityLabel: 'Connect with token or guest access',
      })
      .props.onPress();
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({ accessibilityLabel: 'Open vela-4' })
      .props.onPress();
  });

  expect(mockLoadIssueDetails).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    '2-4',
  );
  expect(mockLoadProjectSchema).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    '0-7',
  );
  expect(mockLoadIssueLinks).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    '2-4',
  );

  const text = renderer!.root
    .findAllByType(Text)
    .flatMap(node =>
      Array.isArray(node.props.children)
        ? node.props.children
        : [node.props.children],
    );

  expect(text).toContain('vela-4');
  expect(text).toContain('Vela');
  expect(text).toContain('vela');
  expect(text).toContain('Fields');
  expect(text).toContain('Links');
});

test('renders saved My Work offline without enabling writes', async () => {
  const account = {
    id: 'account-offline',
    service_url: 'https://saved.youtrack.cloud',
    auth_kind: 'permanent_token' as const,
  };
  mockListAccounts.mockResolvedValueOnce([account]);
  mockLoadCachedMyWork.mockResolvedValueOnce({
    saved_at_ms: 1780000000000,
    data: {
      user: {
        id: '1-1',
        login: 'joshan',
        full_name: 'Joshan',
        email: null,
        guest: false,
      },
      issues: [
        {
          id: '2-9',
          id_readable: 'vela-9',
          summary: 'Available without a connection',
          resolved_at: null,
        },
      ],
    },
  });
  mockRefreshMyWork.mockRejectedValueOnce(new Error('Network is offline'));

  let renderer: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
    await Promise.resolve();
  });

  await ReactTestRenderer.act(async () => {
    renderer!.root
      .findByProps({
        accessibilityLabel: 'Connect https://saved.youtrack.cloud',
      })
      .props.onPress();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  });

  const texts = renderer!.root
    .findAllByType(Text)
    .map(node => JSON.stringify(node.props.children));
  expect(
    texts.some(value => value.includes('Available without a connection')),
  ).toBe(true);
  expect(texts.some(value => value.includes('Offline, cached data'))).toBe(
    true,
  );
  expect(
    renderer!.root.findByProps({ accessibilityLabel: 'New issue' }).props
      .disabled,
  ).toBe(true);
  expect(
    renderer!.root.findByProps({ accessibilityLabel: 'Open vela-9' }).props
      .disabled,
  ).toBe(true);
});
