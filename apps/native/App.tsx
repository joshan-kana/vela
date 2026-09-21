import React from 'react';
import {
  Platform,
  PlatformColor,
  Pressable,
  StatusBar,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';

function App() {
  const dark = useColorScheme() === 'dark';
  const palette =
    Platform.OS === 'macos' ? macOSPalette : dark ? darkPalette : lightPalette;

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

        <View style={styles.emptyState}>
          <Text style={[styles.emptyTitle, { color: palette.text }]}>
            Connect to YouTrack
          </Text>
          <Text
            style={[styles.emptyDescription, { color: palette.secondaryText }]}
          >
            Add a YouTrack account to see your work here.
          </Text>
          <Pressable
            accessibilityRole="button"
            style={({ pressed }) => [
              styles.button,
              { backgroundColor: palette.accent },
              pressed && styles.buttonPressed,
            ]}
          >
            <Text style={styles.buttonText}>Connect</Text>
          </Pressable>
        </View>
      </View>
    </View>
  );
}

const macOSPalette = {
  background: PlatformColor('windowBackgroundColor'),
  sidebar: PlatformColor('controlBackgroundColor'),
  separator: PlatformColor('separatorColor'),
  selection: PlatformColor('unemphasizedSelectedContentBackgroundColor'),
  text: PlatformColor('labelColor'),
  secondaryText: PlatformColor('secondaryLabelColor'),
  accent: PlatformColor('controlAccentColor'),
};

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
  emptyState: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    paddingBottom: 48,
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 8,
  },
  emptyDescription: {
    fontSize: 14,
    marginBottom: 20,
  },
  button: {
    borderRadius: 8,
    paddingHorizontal: 18,
    paddingVertical: 9,
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
