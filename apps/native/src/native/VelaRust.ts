import { NativeModules } from 'react-native';

export type ConnectedUser = {
  id: string;
  login: string;
  full_name: string;
  email: string | null;
  guest: boolean;
};

type VelaRustModule = {
  checkConnection(
    serviceUrl: string,
    bearerToken: string,
  ): Promise<ConnectedUser>;
};

const module = NativeModules.VelaRust as VelaRustModule | undefined;

export async function checkConnection(
  serviceUrl: string,
  bearerToken: string,
): Promise<ConnectedUser> {
  if (!module) {
    throw new Error('Vela Rust bridge is unavailable');
  }

  return module.checkConnection(serviceUrl, bearerToken);
}
