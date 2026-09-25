import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

import SecureStorage from './SecureStorage';

const CHANNEL = 'plugins.it_nomads.com/flutter_secure_storage';

export default class FlutterSecureStorageOhosPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private storage: SecureStorage | null = null;

  getUniqueClassName(): string {
    return 'FlutterSecureStorageOhosPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.storage = new SecureStorage(binding.getApplicationContext());
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.storage = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.dispatch(call, result).catch((): void => {
      result.error('storage_error', `Secure storage ${call.method} failed`, null);
    });
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    const storage = this.storage;
    if (storage === null) {
      throw new Error('Secure storage is detached');
    }

    switch (call.method) {
      case 'write': {
        await storage.write(this.key(call), this.value(call));
        result.success(null);
        return;
      }
      case 'read': {
        result.success(await storage.read(this.key(call)));
        return;
      }
      case 'containsKey': {
        result.success(storage.containsKey(this.key(call)));
        return;
      }
      case 'delete': {
        await storage.delete(this.key(call));
        result.success(null);
        return;
      }
      case 'readAll': {
        result.success(await storage.readAll());
        return;
      }
      case 'deleteAll': {
        await storage.deleteAll();
        result.success(null);
        return;
      }
      default:
        result.notImplemented();
    }
  }

  private key(call: MethodCall): string {
    const args = call.args as Map<string, Object>;
    const key = args.get('key');
    if (typeof key !== 'string') {
      throw new Error('Missing key');
    }
    return key;
  }

  private value(call: MethodCall): string {
    const args = call.args as Map<string, Object>;
    const value = args.get('value');
    if (typeof value !== 'string') {
      throw new Error('Missing value');
    }
    return value;
  }
}
