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
  loadIssueDetails,
  loadIssueLinks,
  loadMyWork,
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
  loadIssueDetails: jest.fn(),
  loadIssueLinks: jest.fn(),
  loadMyWork: jest.fn(),
  loadProjectSchema: jest.fn(),
  setCustomFieldValue: jest.fn(),
  setIssueDescription: jest.fn(),
  setIssueSummary: jest.fn(),
}));

const mockBeginOAuth = jest.mocked(beginOAuth);
const mockListAccounts = jest.mocked(listAccounts);
const mockSavePermanentTokenAccount = jest.mocked(savePermanentTokenAccount);
const mockWithConnection = jest.mocked(withConnection);
const mockLoadMyWork = jest.mocked(loadMyWork);
const mockLoadIssueDetails = jest.mocked(loadIssueDetails);
const mockLoadIssueLinks = jest.mocked(loadIssueLinks);
const mockLoadProjectSchema = jest.mocked(loadProjectSchema);

beforeEach(() => {
  jest.clearAllMocks();
  mockListAccounts.mockResolvedValue([]);
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
    mockLoadMyWork,
  );
  expect(mockLoadMyWork).toHaveBeenCalledWith(
    'https://saved.youtrack.cloud',
    'stored-token',
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
