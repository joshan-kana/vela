import { NativeModules } from 'react-native';

const mockVelaRust: Record<string, jest.Mock> = {
  discoverJson: jest.fn(),
  loadProjectSchemaJson: jest.fn(),
  loadUsersJson: jest.fn(),
  loadAgileBoardsJson: jest.fn(),
  loadSavedQueriesJson: jest.fn(),
};

import {
  discoverYouTrack,
  loadAgileBoards,
  loadProjectSchema,
  loadSavedQueries,
  loadUsers,
  type AgileBoard,
  type ProjectSchema,
  type SavedQuery,
  type UserRef,
  type YouTrackDiscovery,
} from '../src/native/VelaRust';

const discovery: YouTrackDiscovery = {
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
  issue_link_types: {
    capability: 'available',
    items: [],
  },
  agile_boards: 'available',
  saved_queries: 'available',
};

const users: UserRef[] = [
  {
    id: '1-7',
    login: 'admin',
    full_name: 'Admin User',
  },
];

const boards: AgileBoard[] = [
  {
    id: '147-1',
    name: 'Vela board',
    owner: users[0],
  },
];

const savedQueries: SavedQuery[] = [
  {
    id: '4-1',
    name: 'My planned work',
    query: 'project: vela Status: Planned',
    owner: users[0],
  },
];

const schema: ProjectSchema = {
  project: discovery.projects.items[0],
  custom_fields: [
    {
      id: '189-53',
      project_field_type: 'StateProjectCustomField',
      field: {
        id: '161-13',
        name: 'Status',
        localized_name: null,
        aliases: null,
        field_type: {
          id: 'state[1]',
          value_type: 'state',
          is_multi_value: false,
        },
      },
      can_be_empty: false,
      is_public: true,
      ordinal: 1,
      bundle: {
        id: '165-4',
        bundle_type: 'StateBundle',
        values: [
          {
            id: '166-32',
            value_type: 'StateBundleElement',
            display_name: 'Closed',
            localized_name: null,
            archived: false,
            ordinal: 6,
            is_resolved: true,
          },
        ],
      },
    },
  ],
};

beforeEach(() => {
  jest.clearAllMocks();
  delete mockVelaRust.discover;
  delete mockVelaRust.loadProjectSchema;
  delete mockVelaRust.loadUsers;
  delete mockVelaRust.loadAgileBoards;
  delete mockVelaRust.loadSavedQueries;
  NativeModules.VelaRust = mockVelaRust;
});

test('uses direct native discovery when the platform returns objects', async () => {
  mockVelaRust.discover = jest.fn().mockResolvedValue(discovery);

  await expect(
    discoverYouTrack('https://example.youtrack.cloud', ''),
  ).resolves.toEqual(discovery);
  expect(mockVelaRust.discoverJson).not.toHaveBeenCalled();
});

test('uses direct native paginated collections when available', async () => {
  mockVelaRust.loadUsers = jest.fn().mockResolvedValue(users);
  mockVelaRust.loadAgileBoards = jest.fn().mockResolvedValue(boards);
  mockVelaRust.loadSavedQueries = jest.fn().mockResolvedValue(savedQueries);

  await expect(
    loadUsers('https://example.youtrack.cloud', '', 42, 10),
  ).resolves.toEqual(users);
  await expect(
    loadAgileBoards('https://example.youtrack.cloud', '', 0, 10),
  ).resolves.toEqual(boards);
  await expect(
    loadSavedQueries('https://example.youtrack.cloud', '', 0, 10),
  ).resolves.toEqual(savedQueries);

  expect(mockVelaRust.loadUsers).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    42,
    10,
  );
  expect(mockVelaRust.loadUsersJson).not.toHaveBeenCalled();
});

test('decodes Android JSON discovery and project schema responses', async () => {
  mockVelaRust.discoverJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: discovery }),
  );
  mockVelaRust.loadProjectSchemaJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: schema }),
  );

  await expect(
    discoverYouTrack('https://example.youtrack.cloud', ''),
  ).resolves.toEqual(discovery);
  await expect(
    loadProjectSchema('https://example.youtrack.cloud', '', '0-7'),
  ).resolves.toEqual(schema);
});

test('decodes Android JSON paginated collections', async () => {
  mockVelaRust.loadUsersJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: users }),
  );
  mockVelaRust.loadAgileBoardsJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: boards }),
  );
  mockVelaRust.loadSavedQueriesJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: savedQueries }),
  );

  await expect(
    loadUsers('https://example.youtrack.cloud', '', 0, 42),
  ).resolves.toEqual(users);
  await expect(
    loadAgileBoards('https://example.youtrack.cloud', '', 0, 42),
  ).resolves.toEqual(boards);
  await expect(
    loadSavedQueries('https://example.youtrack.cloud', '', 0, 42),
  ).resolves.toEqual(savedQueries);
});

test('surfaces Rust bridge errors from JSON adapters', async () => {
  mockVelaRust.discoverJson.mockResolvedValue(
    JSON.stringify({ status: 'error', message: 'no project access' }),
  );

  await expect(
    discoverYouTrack('https://example.youtrack.cloud', ''),
  ).rejects.toThrow('no project access');
});
