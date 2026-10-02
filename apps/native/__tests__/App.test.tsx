import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import { Text, TextInput } from 'react-native';

import App from '../App';
import { loadMyWork } from '../src/native/VelaRust';

jest.mock('../src/native/VelaRust', () => ({
  loadMyWork: jest.fn(),
}));

const mockLoadMyWork = jest.mocked(loadMyWork);

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
