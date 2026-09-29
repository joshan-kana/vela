import { NativeModules } from 'react-native';

const mockVelaRust: Record<string, jest.Mock> = {
  discoverJson: jest.fn(),
  loadProjectSchemaJson: jest.fn(),
  loadUsersJson: jest.fn(),
  loadAgileBoardsJson: jest.fn(),
  loadSavedQueriesJson: jest.fn(),
  loadIssueDetailsJson: jest.fn(),
  loadIssueLinksJson: jest.fn(),
  setIssueSummaryJson: jest.fn(),
  setIssueDescriptionJson: jest.fn(),
  setCustomFieldValueJson: jest.fn(),
  applyCustomFieldEventJson: jest.fn(),
  executeIssueActionJson: jest.fn(),
};

import {
  applyCustomFieldEvent,
  discoverYouTrack,
  executeIssueAction,
  loadAgileBoards,
  loadIssueDetails,
  loadIssueLinks,
  loadProjectSchema,
  loadSavedQueries,
  loadUsers,
  setCustomFieldValue,
  setIssueDescription,
  setIssueSummary,
  type AgileBoard,
  type IssueAction,
  type IssueDetails,
  type IssueLink,
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

const issueDetails: IssueDetails = {
  id: '3-604',
  id_readable: 'vela-4',
  summary: 'Build issue inspector and generic field editing',
  description: 'Inspector scope',
  created_at: 1780000000000,
  updated_at: 1780001000000,
  resolved_at: null,
  project: discovery.projects.items[0],
  custom_fields: [
    {
      id: '123-4',
      name: 'Status',
      field_type: 'StateMachineIssueCustomField',
      value: {
        id: '166-12',
        name: 'In Progress',
        isResolved: false,
      },
      possible_events: [
        {
          id: 'review',
          presentation: 'Review',
        },
      ],
    },
  ],
};

const issueLinks: IssueLink[] = [
  {
    id: '173-3t',
    direction: 'INWARD',
    link_type: {
      id: '173-3',
      name: 'Subtask',
      source_to_target: 'parent for',
      target_to_source: 'subtask of',
      directed: true,
      aggregation: true,
      read_only: false,
    },
    issues: [
      {
        id: '3-603',
        id_readable: 'vela-1',
        summary: 'First usable Vela client',
        resolved_at: null,
      },
    ],
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
  delete mockVelaRust.loadIssueDetails;
  delete mockVelaRust.loadIssueLinks;
  delete mockVelaRust.setIssueSummary;
  delete mockVelaRust.setIssueDescription;
  delete mockVelaRust.setCustomFieldValue;
  delete mockVelaRust.applyCustomFieldEvent;
  delete mockVelaRust.executeIssueAction;
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

test('uses the shared direct issue action method when available', async () => {
  const action: IssueAction = {
    kind: 'create_issue',
    project_id: '0-7',
    summary: 'Create from Vela',
    description: null,
  };
  const result = { kind: 'issue' as const, issue: issueDetails };
  mockVelaRust.executeIssueAction = jest.fn().mockResolvedValue(result);

  await expect(
    executeIssueAction('https://example.youtrack.cloud', 'token', action),
  ).resolves.toEqual(result);

  expect(mockVelaRust.executeIssueActionJson).not.toHaveBeenCalled();
});

test('serializes actions through the Android JSON adapter', async () => {
  const action: IssueAction = {
    kind: 'set_priority',
    issue_id: 'vela-5',
    change: {
      mode: 'value',
      field_id: '123-4',
      field_type: 'SingleEnumIssueCustomField',
      value: { id: 'enum-1' },
    },
  };
  const result = { kind: 'issue' as const, issue: issueDetails };
  mockVelaRust.executeIssueActionJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: result }),
  );

  await expect(
    executeIssueAction('https://example.youtrack.cloud', '', action),
  ).resolves.toEqual(result);

  expect(mockVelaRust.executeIssueActionJson).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    JSON.stringify(action),
  );
});

test('uses direct issue detail and editing methods when available', async () => {
  mockVelaRust.loadIssueDetails = jest.fn().mockResolvedValue(issueDetails);
  mockVelaRust.loadIssueLinks = jest.fn().mockResolvedValue(issueLinks);
  mockVelaRust.setIssueSummary = jest.fn().mockResolvedValue(issueDetails);
  mockVelaRust.setIssueDescription = jest.fn().mockResolvedValue(issueDetails);
  mockVelaRust.setCustomFieldValue = jest
    .fn()
    .mockResolvedValue(issueDetails.custom_fields[0]);
  mockVelaRust.applyCustomFieldEvent = jest
    .fn()
    .mockResolvedValue(issueDetails.custom_fields[0]);

  await expect(
    loadIssueDetails('https://example.youtrack.cloud', 'token', 'vela-4'),
  ).resolves.toEqual(issueDetails);
  await expect(
    loadIssueLinks('https://example.youtrack.cloud', 'token', 'vela-4'),
  ).resolves.toEqual(issueLinks);
  await expect(
    setIssueSummary(
      'https://example.youtrack.cloud',
      'token',
      'vela-4',
      'Updated summary',
    ),
  ).resolves.toEqual(issueDetails);
  await expect(
    setIssueDescription(
      'https://example.youtrack.cloud',
      'token',
      'vela-4',
      null,
    ),
  ).resolves.toEqual(issueDetails);
  await expect(
    setCustomFieldValue(
      'https://example.youtrack.cloud',
      'token',
      'vela-4',
      '123-4',
      'StateMachineIssueCustomField',
      { id: '166-12' },
    ),
  ).resolves.toEqual(issueDetails.custom_fields[0]);
  await expect(
    applyCustomFieldEvent(
      'https://example.youtrack.cloud',
      'token',
      'vela-4',
      '123-4',
      'StateMachineIssueCustomField',
      'review',
    ),
  ).resolves.toEqual(issueDetails.custom_fields[0]);

  expect(mockVelaRust.loadIssueDetailsJson).not.toHaveBeenCalled();
  expect(mockVelaRust.setCustomFieldValueJson).not.toHaveBeenCalled();
});

test('decodes Android issue detail adapters and serializes custom field values', async () => {
  const field = issueDetails.custom_fields[0];

  mockVelaRust.loadIssueDetailsJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: issueDetails }),
  );
  mockVelaRust.loadIssueLinksJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: issueLinks }),
  );
  mockVelaRust.setIssueSummaryJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: issueDetails }),
  );
  mockVelaRust.setIssueDescriptionJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: issueDetails }),
  );
  mockVelaRust.setCustomFieldValueJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: field }),
  );
  mockVelaRust.applyCustomFieldEventJson.mockResolvedValue(
    JSON.stringify({ status: 'ok', data: field }),
  );

  await expect(
    loadIssueDetails('https://example.youtrack.cloud', '', 'vela-4'),
  ).resolves.toEqual(issueDetails);
  await expect(
    loadIssueLinks('https://example.youtrack.cloud', '', 'vela-4'),
  ).resolves.toEqual(issueLinks);
  await expect(
    setIssueSummary(
      'https://example.youtrack.cloud',
      '',
      'vela-4',
      'Updated summary',
    ),
  ).resolves.toEqual(issueDetails);
  await expect(
    setIssueDescription('https://example.youtrack.cloud', '', 'vela-4', null),
  ).resolves.toEqual(issueDetails);
  await expect(
    setCustomFieldValue(
      'https://example.youtrack.cloud',
      '',
      'vela-4',
      '123-4',
      'StateMachineIssueCustomField',
      { id: '166-12' },
    ),
  ).resolves.toEqual(field);
  await expect(
    applyCustomFieldEvent(
      'https://example.youtrack.cloud',
      '',
      'vela-4',
      '123-4',
      'StateMachineIssueCustomField',
      'review',
    ),
  ).resolves.toEqual(field);

  expect(mockVelaRust.setCustomFieldValueJson).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    'vela-4',
    '123-4',
    'StateMachineIssueCustomField',
    JSON.stringify({ id: '166-12' }),
  );
  expect(mockVelaRust.setIssueDescriptionJson).toHaveBeenCalledWith(
    'https://example.youtrack.cloud',
    '',
    'vela-4',
    null,
  );
});

test('surfaces Rust bridge errors from JSON adapters', async () => {
  mockVelaRust.discoverJson.mockResolvedValue(
    JSON.stringify({ status: 'error', message: 'no project access' }),
  );

  await expect(
    discoverYouTrack('https://example.youtrack.cloud', ''),
  ).rejects.toThrow('no project access');
});
