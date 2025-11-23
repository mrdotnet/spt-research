/**
 * Settings Dialog Component
 * Manages application settings including AI provider configuration
 * Supports Azure AI Foundry (Claude via Azure) and direct Anthropic API
 */

import * as React from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import { Settings, X, Cloud, Key, RefreshCw, Check, AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { cn } from '@/lib/utils';
import { aiService } from '@/services/ai';
import type { AIProvider } from '@/services/ai';

export interface SettingsDialogProps {
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}

type ConnectionStatus = 'idle' | 'testing' | 'success' | 'error';

export function SettingsDialog({ open: controlledOpen, onOpenChange }: SettingsDialogProps) {
  const [open, setOpen] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(false);
  const [saveStatus, setSaveStatus] = React.useState<'idle' | 'success' | 'error'>('idle');

  // Provider selection
  const [activeProvider, setActiveProvider] = React.useState<AIProvider>('azure');

  // Azure AI Foundry settings
  const [azureEndpoint, setAzureEndpoint] = React.useState('https://models.inference.ai.azure.com');
  const [azureApiKey, setAzureApiKey] = React.useState('');
  const [azureConnectionStatus, setAzureConnectionStatus] = React.useState<ConnectionStatus>('idle');

  // Anthropic settings (fallback)
  const [anthropicApiKey, setAnthropicApiKey] = React.useState('');
  const [anthropicConnectionStatus, setAnthropicConnectionStatus] = React.useState<ConnectionStatus>('idle');

  const isControlled = controlledOpen !== undefined;
  const isOpen = isControlled ? controlledOpen : open;

  const handleOpenChange = (newOpen: boolean) => {
    if (isControlled) {
      onOpenChange?.(newOpen);
    } else {
      setOpen(newOpen);
    }
  };

  // Load settings when dialog opens
  React.useEffect(() => {
    if (isOpen) {
      loadSettings();
    }
  }, [isOpen]);

  const loadSettings = async () => {
    try {
      setIsLoading(true);

      // Load Azure settings
      const azureEndpointResult = await window.electron.invoke('settings:get', 'azure_ai_endpoint');
      if (azureEndpointResult?.value) {
        setAzureEndpoint(azureEndpointResult.value);
      }

      const azureKeyResult = await window.electron.invoke('settings:get', 'azure_ai_key');
      if (azureKeyResult?.value) {
        setAzureApiKey('ghp_' + '•'.repeat(36)); // Mask GitHub token format
      }

      // Load Anthropic settings
      const anthropicKeyResult = await window.electron.invoke('settings:get', 'anthropic_api_key');
      if (anthropicKeyResult?.value) {
        setAnthropicApiKey('sk-ant-' + '•'.repeat(40));
      }

      // Load active provider
      const providerResult = await window.electron.invoke('settings:get', 'ai_provider');
      if (providerResult?.value) {
        setActiveProvider(providerResult.value as AIProvider);
      }
    } catch (error) {
      console.error('Failed to load settings:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const testAzureConnection = async () => {
    if (!azureApiKey || azureApiKey.includes('•')) {
      return;
    }

    setAzureConnectionStatus('testing');
    try {
      // Initialize temporarily for testing
      aiService.initialize({
        provider: 'azure',
        azure: {
          endpoint: azureEndpoint,
          apiKey: azureApiKey,
        },
      });

      const success = await aiService.testConnection();
      setAzureConnectionStatus(success ? 'success' : 'error');
    } catch {
      setAzureConnectionStatus('error');
    }
  };

  const testAnthropicConnection = async () => {
    if (!anthropicApiKey || anthropicApiKey.includes('•')) {
      return;
    }

    setAnthropicConnectionStatus('testing');
    try {
      aiService.initialize({
        provider: 'anthropic',
        anthropic: {
          apiKey: anthropicApiKey,
        },
      });

      const success = await aiService.testConnection();
      setAnthropicConnectionStatus(success ? 'success' : 'error');
    } catch {
      setAnthropicConnectionStatus('error');
    }
  };

  const handleSave = async () => {
    try {
      setIsLoading(true);
      setSaveStatus('idle');

      // Save Azure settings
      if (azureEndpoint) {
        await window.electron.invoke('settings:set', 'azure_ai_endpoint', azureEndpoint);
      }
      if (azureApiKey && !azureApiKey.includes('•')) {
        await window.electron.invoke('settings:set', 'azure_ai_key', azureApiKey);
      }

      // Save Anthropic settings
      if (anthropicApiKey && !anthropicApiKey.includes('•')) {
        await window.electron.invoke('settings:set', 'anthropic_api_key', anthropicApiKey);
      }

      // Save active provider
      await window.electron.invoke('settings:set', 'ai_provider', activeProvider);

      // Initialize AI service with saved settings
      const config: Parameters<typeof aiService.initialize>[0] = {
        provider: activeProvider,
      };

      // Get actual keys (not masked ones)
      const actualAzureKey = azureApiKey.includes('•')
        ? (await window.electron.invoke('settings:get', 'azure_ai_key'))?.value
        : azureApiKey;

      const actualAnthropicKey = anthropicApiKey.includes('•')
        ? (await window.electron.invoke('settings:get', 'anthropic_api_key'))?.value
        : anthropicApiKey;

      if (actualAzureKey) {
        config.azure = {
          endpoint: azureEndpoint,
          apiKey: actualAzureKey,
        };
      }

      if (actualAnthropicKey) {
        config.anthropic = {
          apiKey: actualAnthropicKey,
        };
      }

      aiService.initialize(config);
      console.log(`✅ AI Service initialized with ${activeProvider} provider`);

      setSaveStatus('success');
      setTimeout(() => {
        handleOpenChange(false);
      }, 1000);
    } catch (error) {
      console.error('Failed to save settings:', error);
      setSaveStatus('error');
    } finally {
      setIsLoading(false);
    }
  };

  const renderConnectionStatus = (status: ConnectionStatus) => {
    switch (status) {
      case 'testing':
        return <RefreshCw className="h-4 w-4 animate-spin text-blue-500" />;
      case 'success':
        return <Check className="h-4 w-4 text-green-500" />;
      case 'error':
        return <AlertCircle className="h-4 w-4 text-red-500" />;
      default:
        return null;
    }
  };

  return (
    <Dialog.Root open={isOpen} onOpenChange={handleOpenChange}>
      <Dialog.Trigger asChild>
        <Button variant="ghost" size="icon" aria-label="Settings">
          <Settings className="h-5 w-5" />
        </Button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/50 backdrop-blur-sm data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
        <Dialog.Content
          className={cn(
            'fixed left-[50%] top-[50%] z-50 grid w-full max-w-2xl translate-x-[-50%] translate-y-[-50%] gap-6 border border-gray-200 bg-white p-6 shadow-xl duration-200',
            'rounded-2xl max-h-[90vh] overflow-y-auto',
            'data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%]'
          )}
        >
          {/* Header */}
          <div className="flex items-center justify-between">
            <Dialog.Title className="text-2xl font-semibold text-gray-900">
              Settings
            </Dialog.Title>
            <Dialog.Close asChild>
              <Button variant="ghost" size="icon" aria-label="Close">
                <X className="h-5 w-5" />
              </Button>
            </Dialog.Close>
          </div>

          {/* Provider Selection */}
          <div className="space-y-4">
            <h3 className="text-sm font-medium text-gray-700">AI Provider</h3>
            <div className="grid grid-cols-2 gap-3">
              <button
                onClick={() => setActiveProvider('azure')}
                className={cn(
                  'flex items-center gap-3 rounded-lg border-2 p-4 transition-all',
                  activeProvider === 'azure'
                    ? 'border-blue-500 bg-blue-50'
                    : 'border-gray-200 hover:border-gray-300'
                )}
              >
                <Cloud className={cn('h-6 w-6', activeProvider === 'azure' ? 'text-blue-500' : 'text-gray-400')} />
                <div className="text-left">
                  <div className={cn('font-medium', activeProvider === 'azure' ? 'text-blue-700' : 'text-gray-700')}>
                    Azure AI Foundry
                  </div>
                  <div className="text-xs text-gray-500">Claude via Azure</div>
                </div>
              </button>

              <button
                onClick={() => setActiveProvider('anthropic')}
                className={cn(
                  'flex items-center gap-3 rounded-lg border-2 p-4 transition-all',
                  activeProvider === 'anthropic'
                    ? 'border-orange-500 bg-orange-50'
                    : 'border-gray-200 hover:border-gray-300'
                )}
              >
                <Key className={cn('h-6 w-6', activeProvider === 'anthropic' ? 'text-orange-500' : 'text-gray-400')} />
                <div className="text-left">
                  <div className={cn('font-medium', activeProvider === 'anthropic' ? 'text-orange-700' : 'text-gray-700')}>
                    Anthropic Direct
                  </div>
                  <div className="text-xs text-gray-500">Direct API access</div>
                </div>
              </button>
            </div>
          </div>

          {/* Azure AI Foundry Settings */}
          <div className={cn('space-y-4 rounded-lg border p-4', activeProvider === 'azure' ? 'border-blue-200 bg-blue-50/50' : 'border-gray-200')}>
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium text-gray-700">Azure AI Foundry (Claude)</h3>
              {renderConnectionStatus(azureConnectionStatus)}
            </div>

            <Input
              label="Endpoint"
              type="url"
              value={azureEndpoint}
              onChange={(e) => setAzureEndpoint(e.target.value)}
              placeholder="https://models.inference.ai.azure.com"
              helperText="Azure AI inference endpoint"
              disabled={isLoading}
            />

            <div className="flex gap-2">
              <div className="flex-1">
                <Input
                  label="API Key / GitHub Token"
                  type="password"
                  value={azureApiKey}
                  onChange={(e) => {
                    setAzureApiKey(e.target.value);
                    setAzureConnectionStatus('idle');
                  }}
                  placeholder="ghp_xxxx... or Azure API key"
                  helperText="GitHub PAT for serverless Claude or Azure API key"
                  disabled={isLoading}
                />
              </div>
              <div className="flex items-end pb-5">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={testAzureConnection}
                  disabled={isLoading || !azureApiKey || azureApiKey.includes('•')}
                >
                  Test
                </Button>
              </div>
            </div>
          </div>

          {/* Anthropic Settings */}
          <div className={cn('space-y-4 rounded-lg border p-4', activeProvider === 'anthropic' ? 'border-orange-200 bg-orange-50/50' : 'border-gray-200')}>
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-medium text-gray-700">Anthropic Direct (Fallback)</h3>
              {renderConnectionStatus(anthropicConnectionStatus)}
            </div>

            <div className="flex gap-2">
              <div className="flex-1">
                <Input
                  label="Anthropic API Key"
                  type="password"
                  value={anthropicApiKey}
                  onChange={(e) => {
                    setAnthropicApiKey(e.target.value);
                    setAnthropicConnectionStatus('idle');
                  }}
                  placeholder="sk-ant-..."
                  helperText="Direct Anthropic API key (optional fallback)"
                  disabled={isLoading}
                />
              </div>
              <div className="flex items-end pb-5">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={testAnthropicConnection}
                  disabled={isLoading || !anthropicApiKey || anthropicApiKey.includes('•')}
                >
                  Test
                </Button>
              </div>
            </div>
          </div>

          {/* Status Messages */}
          {saveStatus === 'success' && (
            <div className="rounded-lg bg-green-50 p-3 text-sm text-green-800">
              Settings saved successfully!
            </div>
          )}
          {saveStatus === 'error' && (
            <div className="rounded-lg bg-red-50 p-3 text-sm text-red-800">
              Failed to save settings. Please try again.
            </div>
          )}

          {/* Footer */}
          <div className="flex justify-end gap-3">
            <Dialog.Close asChild>
              <Button variant="ghost" disabled={isLoading}>
                Cancel
              </Button>
            </Dialog.Close>
            <Button onClick={handleSave} disabled={isLoading}>
              {isLoading ? 'Saving...' : 'Save Settings'}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
