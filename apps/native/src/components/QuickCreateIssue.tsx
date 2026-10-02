import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { withConnection, type Connection } from '../native/AccountStore';
import {
  discoverYouTrack,
  executeIssueAction,
  type IssueDetails,
  type ProjectRef,
} from '../native/VelaRust';
import type { InspectorPalette } from './IssueInspector';

type Props = {
  connection: Connection;
  palette: InspectorPalette;
  onCancel(): void;
  onCreated(issue: IssueDetails): void;
};

export default function QuickCreateIssue({
  connection,
  palette,
  onCancel,
  onCreated,
}: Props) {
  const [projects, setProjects] = useState<ProjectRef[]>([]);
  const [selectedProject, setSelectedProject] = useState<ProjectRef | null>(
    null,
  );
  const [projectQuery, setProjectQuery] = useState('');
  const [summary, setSummary] = useState('');
  const [description, setDescription] = useState('');
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;

    async function loadProjects() {
      try {
        const discovery = await withConnection(connection, discoverYouTrack);

        if (!active) {
          return;
        }

        if (discovery.projects.capability !== 'available') {
          setError('Projects are not available for this YouTrack account.');
          return;
        }

        const available = discovery.projects.items
          .filter(project => project.archived !== true)
          .sort((left, right) => left.name.localeCompare(right.name));

        setProjects(available);
        if (available.length === 1) {
          setSelectedProject(available[0]);
        }
      } catch (loadError) {
        if (active) {
          setError(message(loadError, 'Unable to load projects'));
        }
      } finally {
        if (active) {
          setLoading(false);
        }
      }
    }

    loadProjects();

    return () => {
      active = false;
    };
  }, [connection]);

  const matchingProjects = useMemo(() => {
    const query = projectQuery.trim().toLocaleLowerCase();
    const matches = query
      ? projects.filter(
          project =>
            project.name.toLocaleLowerCase().includes(query) ||
            project.short_name.toLocaleLowerCase().includes(query),
        )
      : projects;

    return matches.slice(0, 12);
  }, [projectQuery, projects]);

  async function createIssue() {
    if (!selectedProject || !summary.trim() || creating) {
      return;
    }

    setCreating(true);
    setError(null);

    try {
      const result = await withConnection(
        connection,
        (serviceUrl, bearerToken) =>
          executeIssueAction(serviceUrl, bearerToken, {
            kind: 'create_issue',
            project_id: selectedProject.id,
            summary: summary.trim(),
            description: description.trim() || null,
          }),
      );

      if (result.kind !== 'issue') {
        throw new Error('YouTrack did not return the created issue');
      }

      onCreated(result.issue);
    } catch (createError) {
      setError(message(createError, 'Unable to create the issue'));
    } finally {
      setCreating(false);
    }
  }

  return (
    <View style={styles.root}>
      <View style={[styles.toolbar, { borderColor: palette.separator }]}>
        <Pressable
          accessibilityRole="button"
          onPress={onCancel}
          style={({ pressed }) => [
            styles.backButton,
            { backgroundColor: palette.selection },
            pressed && styles.pressed,
          ]}
        >
          <Text style={{ color: palette.text }}>‹ My Work</Text>
        </Pressable>
        <Text style={[styles.heading, { color: palette.text }]}>New issue</Text>
      </View>

      {loading ? (
        <View style={styles.centered}>
          <ActivityIndicator />
        </View>
      ) : (
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
        >
          <Text style={[styles.label, { color: palette.secondaryText }]}>
            Project
          </Text>
          <TextInput
            accessibilityLabel="Find project"
            autoCapitalize="none"
            autoCorrect={false}
            onChangeText={setProjectQuery}
            placeholder="Find a project"
            placeholderTextColor={palette.secondaryText}
            style={[
              styles.input,
              { borderColor: palette.separator, color: palette.text },
            ]}
            value={projectQuery}
          />

          <View style={styles.projects}>
            {matchingProjects.map(project => {
              const selected = selectedProject?.id === project.id;
              return (
                <Pressable
                  accessibilityLabel={`Select ${project.name}`}
                  accessibilityRole="button"
                  key={project.id}
                  onPress={() => setSelectedProject(project)}
                  style={({ pressed }) => [
                    styles.projectRow,
                    {
                      backgroundColor: selected
                        ? palette.selection
                        : palette.background,
                      borderColor: palette.separator,
                    },
                    pressed && styles.pressed,
                  ]}
                >
                  <Text style={[styles.projectName, { color: palette.text }]}>
                    {project.name}
                  </Text>
                  <Text style={{ color: palette.secondaryText }}>
                    {project.short_name}
                  </Text>
                </Pressable>
              );
            })}
          </View>

          {projects.length > matchingProjects.length ? (
            <Text style={{ color: palette.secondaryText }}>
              Type to narrow the project list.
            </Text>
          ) : null}

          <Text style={[styles.label, { color: palette.secondaryText }]}>
            Summary
          </Text>
          <TextInput
            accessibilityLabel="New issue summary"
            autoFocus={selectedProject !== null}
            editable={!creating}
            onChangeText={setSummary}
            onSubmitEditing={() => {
              createIssue();
            }}
            placeholder="What needs doing?"
            placeholderTextColor={palette.secondaryText}
            returnKeyType="done"
            style={[
              styles.input,
              { borderColor: palette.separator, color: palette.text },
            ]}
            value={summary}
          />

          <Text style={[styles.label, { color: palette.secondaryText }]}>
            Description
          </Text>
          <TextInput
            accessibilityLabel="New issue description"
            editable={!creating}
            multiline
            onChangeText={setDescription}
            placeholder="Optional"
            placeholderTextColor={palette.secondaryText}
            style={[
              styles.description,
              { borderColor: palette.separator, color: palette.text },
            ]}
            textAlignVertical="top"
            value={description}
          />

          {error ? <Text style={styles.error}>{error}</Text> : null}

          <Pressable
            accessibilityLabel="Create issue"
            accessibilityRole="button"
            disabled={!selectedProject || !summary.trim() || creating}
            onPress={() => {
              createIssue();
            }}
            style={({ pressed }) => [
              styles.createButton,
              { backgroundColor: palette.accent },
              (!selectedProject || !summary.trim() || creating) &&
                styles.disabled,
              pressed && styles.pressed,
            ]}
          >
            {creating ? (
              <ActivityIndicator color="#ffffff" size="small" />
            ) : (
              <Text style={styles.createButtonText}>Create issue</Text>
            )}
          </Pressable>
        </ScrollView>
      )}
    </View>
  );
}

function message(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback;
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
  toolbar: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 14,
    paddingBottom: 12,
  },
  backButton: {
    borderRadius: 7,
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  heading: {
    fontSize: 22,
    fontWeight: '600',
  },
  centered: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
  content: {
    gap: 10,
    maxWidth: 620,
    paddingBottom: 40,
    paddingTop: 20,
  },
  label: {
    fontSize: 12,
    fontWeight: '600',
    marginTop: 8,
  },
  input: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    fontSize: 14,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  projects: {
    gap: 5,
  },
  projectRow: {
    alignItems: 'center',
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  projectName: {
    flex: 1,
    fontSize: 14,
    marginRight: 12,
  },
  description: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    fontSize: 14,
    minHeight: 120,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  error: {
    color: '#d93025',
    fontSize: 13,
  },
  createButton: {
    alignItems: 'center',
    alignSelf: 'flex-start',
    borderRadius: 8,
    minHeight: 36,
    justifyContent: 'center',
    marginTop: 8,
    paddingHorizontal: 18,
    paddingVertical: 9,
  },
  createButtonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
  disabled: {
    opacity: 0.45,
  },
  pressed: {
    opacity: 0.8,
  },
});
