import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import { Text, TextInput } from 'react-native';

import App from '../App';
import {
  loadIssueDetails,
  loadIssueLinks,
  loadMyWork,
  loadProjectSchema,
} from '../src/native/VelaRust';

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

const mockLoadMyWork = jest.mocked(loadMyWork);
const mockLoadIssueDetails = jest.mocked(loadIssueDetails);
const mockLoadIssueLinks = jest.mocked(loadIssueLinks);
const mockLoadProjectSchema = jest.mocked(loadProjectSchema);

test('renders the YouTrack connection form', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer;

  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const text = renderer!.root
    .findAllByType(Text)
    .map(node => node.props.children);

  expect(text).toContain('My Work');
  expect(text).toContain('Connect to YouTrack');
  expect(renderer!.root.findAllByType(TextInput)).toHaveLength(2);
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

  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const address = renderer!.root.findAllByType(TextInput)[0];

  await ReactTestRenderer.act(() => {
    address.props.onChangeText('https://example.youtrack.cloud');
  });

  const connect = renderer!.root.findByProps({ accessibilityRole: 'button' });

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

  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const address = renderer!.root.findAllByType(TextInput)[0];
  await ReactTestRenderer.act(() => {
    address.props.onChangeText('https://example.youtrack.cloud');
  });

  await ReactTestRenderer.act(async () => {
    await renderer!.root
      .findByProps({ accessibilityRole: 'button' })
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
