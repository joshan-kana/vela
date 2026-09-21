import React, { useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  useColorScheme,
  View,
} from 'react-native';

import { loadMyWork, type MyWork } from './src/native/VelaRust';

const ISSUE_ROW_HEIGHT = 42;

function App() {
  const dark = useColorScheme() === 'dark';
  const palette = dark ? darkPalette : lightPalette;

  const [serviceUrl, setServiceUrl] = useState('');
  const [token, setToken] = useState('');
  const [work, setWork] = useState<MyWork | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [connecting, setConnecting] = useState(false);

  async function connect() {
    const trimmedUrl = serviceUrl.trim();
    if (!trimmedUrl || connecting) {
      return;
    }

    setConnecting(true);
    setError(null);

    try {
      const loadedWork = await loadMyWork(trimmedUrl, token);
      setWork(loadedWork);
      setToken('');
    } catch (connectionError) {
      setWork(null);
      setError(
        connectionError instanceof Error
          ? connectionError.message
          : 'Unable to connect to YouTrack',
      );
    } finally {
      setConnecting(false);
    }
  }

  return (
    <View style={[styles.window, { backgroundColor: palette.background }]}>
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />

      <View
        style={[
          styles.sidebar,
          {
            backgroundColor: palette.sidebar,
            borderColor: palette.separator,
          },
        ]}
      >
        <Text style={[styles.appName, { color: palette.text }]}>Vela</Text>

        <View style={styles.navigation}>
          <View
            style={[
              styles.navigationItem,
              { backgroundColor: palette.selection },
            ]}
          >
            <Text style={[styles.navigationText, { color: palette.text }]}>
              My Work
            </Text>
          </View>

          <View style={styles.navigationItem}>
            <Text
              style={[styles.navigationText, { color: palette.secondaryText }]}
            >
              Projects
            </Text>
          </View>
        </View>
      </View>

      <View style={styles.content}>
        <Text style={[styles.heading, { color: palette.text }]}>My Work</Text>

        {work ? (
          <View style={styles.work}>
            <View
              style={[styles.accountBar, { borderColor: palette.separator }]}
            >
              <Text style={[styles.accountName, { color: palette.text }]}>
                {work.user.full_name}
              </Text>
              <Text style={{ color: palette.secondaryText }}>
                {work.user.login}
                {work.user.guest ? ' · Guest access' : ''}
              </Text>
            </View>

            <FlatList
              initialNumToRender={20}
              maxToRenderPerBatch={20}
              windowSize={5}
              removeClippedSubviews
              getItemLayout={(_, index) => ({
                length: ISSUE_ROW_HEIGHT,
                offset: ISSUE_ROW_HEIGHT * index,
                index,
              })}
              contentContainerStyle={
                work.issues.length === 0 ? styles.emptyList : undefined
              }
              data={work.issues}
              keyExtractor={issue => issue.id}
              ListEmptyComponent={
                <Text style={{ color: palette.secondaryText }}>
                  No unresolved issues assigned to you.
                </Text>
              }
              renderItem={({ item }) => (
                <View
                  style={[styles.issueRow, { borderColor: palette.separator }]}
                >
                  <Text style={[styles.issueMarker, { color: palette.accent }]}>
                    ○
                  </Text>
                  <Text
                    style={[styles.issueId, { color: palette.secondaryText }]}
                  >
                    {item.id_readable}
                  </Text>
                  <Text
                    numberOfLines={1}
                    style={[styles.issueSummary, { color: palette.text }]}
                  >
                    {item.summary}
                  </Text>
                </View>
              )}
            />
          </View>
        ) : (
          <View style={styles.connectionState}>
            <Text style={[styles.connectionTitle, { color: palette.text }]}>
              Connect to YouTrack
            </Text>
            <Text
              style={[
                styles.connectionDescription,
                { color: palette.secondaryText },
              ]}
            >
              Enter your YouTrack address and, if required, a permanent token.
            </Text>

            <View style={styles.form}>
              <TextInput
                accessibilityLabel="YouTrack address"
                autoCapitalize="none"
                autoCorrect={false}
                onChangeText={setServiceUrl}
                onSubmitEditing={connect}
                placeholder="https://youtrack.example.com"
                placeholderTextColor={palette.secondaryText}
                style={[
                  styles.input,
                  {
                    borderColor: palette.separator,
                    color: palette.text,
                  },
                ]}
                value={serviceUrl}
              />
              <TextInput
                accessibilityLabel="Permanent token"
                autoCapitalize="none"
                autoCorrect={false}
                onChangeText={setToken}
                onSubmitEditing={connect}
                placeholder="Permanent token (optional)"
                placeholderTextColor={palette.secondaryText}
                secureTextEntry
                style={[
                  styles.input,
                  {
                    borderColor: palette.separator,
                    color: palette.text,
                  },
                ]}
                value={token}
              />

              {error ? <Text style={styles.errorText}>{error}</Text> : null}

              <Pressable
                accessibilityRole="button"
                disabled={!serviceUrl.trim() || connecting}
                onPress={connect}
                style={({ pressed }) => [
                  styles.button,
                  { backgroundColor: palette.accent },
                  (!serviceUrl.trim() || connecting) && styles.buttonDisabled,
                  pressed && styles.buttonPressed,
                ]}
              >
                {connecting ? (
                  <ActivityIndicator color="#ffffff" size="small" />
                ) : (
                  <Text style={styles.buttonText}>Connect</Text>
                )}
              </Pressable>
            </View>
          </View>
        )}
      </View>
    </View>
  );
}

const lightPalette = {
  background: '#ffffff',
  sidebar: '#f5f5f5',
  separator: '#dddddd',
  selection: '#e7e7e7',
  text: '#171717',
  secondaryText: '#666666',
  accent: '#2563eb',
};

const darkPalette = {
  background: '#1e1e1e',
  sidebar: '#262626',
  separator: '#3a3a3a',
  selection: '#383838',
  text: '#f4f4f4',
  secondaryText: '#a3a3a3',
  accent: '#3b82f6',
};

const styles = StyleSheet.create({
  window: {
    flex: 1,
    flexDirection: 'row',
    minHeight: 480,
  },
  sidebar: {
    width: 220,
    borderRightWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 14,
    paddingTop: 20,
  },
  appName: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 24,
    paddingHorizontal: 8,
  },
  navigation: {
    gap: 4,
  },
  navigationItem: {
    borderRadius: 7,
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  navigationText: {
    fontSize: 14,
    fontWeight: '500',
  },
  content: {
    flex: 1,
    padding: 32,
  },
  heading: {
    fontSize: 28,
    fontWeight: '600',
  },
  work: {
    flex: 1,
    marginTop: 24,
  },
  accountBar: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    marginBottom: 4,
    paddingBottom: 14,
  },
  accountName: {
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 2,
  },
  issueRow: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    minHeight: ISSUE_ROW_HEIGHT,
    paddingHorizontal: 4,
  },
  issueMarker: {
    fontSize: 17,
    marginRight: 10,
  },
  issueId: {
    fontSize: 12,
    marginRight: 12,
    width: 82,
  },
  issueSummary: {
    flex: 1,
    fontSize: 14,
  },
  emptyList: {
    alignItems: 'center',
    flexGrow: 1,
    justifyContent: 'center',
  },
  connectionState: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    paddingBottom: 48,
  },
  connectionTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 8,
  },
  connectionDescription: {
    fontSize: 14,
    marginBottom: 20,
    maxWidth: 420,
    textAlign: 'center',
  },
  form: {
    gap: 10,
    width: 360,
  },
  input: {
    borderRadius: 7,
    borderWidth: StyleSheet.hairlineWidth,
    fontSize: 14,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  errorText: {
    color: '#d93025',
    fontSize: 13,
  },
  button: {
    alignItems: 'center',
    borderRadius: 8,
    minHeight: 36,
    justifyContent: 'center',
    paddingHorizontal: 18,
    paddingVertical: 9,
  },
  buttonDisabled: {
    opacity: 0.45,
  },
  buttonPressed: {
    opacity: 0.8,
  },
  buttonText: {
    color: '#ffffff',
    fontSize: 14,
    fontWeight: '600',
  },
});

export default App;
