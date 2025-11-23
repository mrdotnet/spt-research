/**
 * Unified AI Service
 * Abstracts between Azure AI Foundry and direct Anthropic API
 * Supports automatic failover and provider switching
 */

import Anthropic from '@anthropic-ai/sdk';
import { AzureAIProvider, azureAIProvider } from './AzureAIProvider';
import type {
  AIConfig,
  AIExecuteOptions,
  AIResponse,
  AIProvider,
  AIModel,
  StreamChunk,
  Artifact,
  ToolUse,
  MODEL_MAPPING,
} from './types';

// Re-export types for backwards compatibility
export type {
  AIExecuteOptions,
  AIResponse,
  AIProvider,
  AIModel,
  StreamChunk,
  Artifact,
  ToolUse,
};

// Legacy type aliases for ClaudeService compatibility
export type ClaudeModel = AIModel;
export type ClaudeExecuteOptions = AIExecuteOptions;
export type ClaudeResponse = AIResponse;

/**
 * Sanitize header value for browser compatibility
 */
function sanitizeHeaderValue(value: string): string {
  return value.replace(/[^\x00-\xFF]/g, '?');
}

/**
 * Patch Headers class for Electron compatibility
 */
function patchHeadersForBrowser(): void {
  if (typeof window === 'undefined') return;
  const globalScope = window as unknown as { __HEADERS_PATCHED__?: boolean; Headers: typeof Headers };
  if (globalScope.__HEADERS_PATCHED__) return;

  const OriginalHeaders = globalScope.Headers;
  if (!OriginalHeaders) return;

  class SafeHeaders extends OriginalHeaders {
    constructor(init?: HeadersInit) {
      super();
      if (init) {
        if (init instanceof Headers) {
          init.forEach((value, key) => {
            super.append(key, sanitizeHeaderValue(value));
          });
        } else if (Array.isArray(init)) {
          for (const [key, value] of init) {
            super.append(key, sanitizeHeaderValue(value));
          }
        } else if (typeof init === 'object') {
          for (const [key, value] of Object.entries(init)) {
            super.append(key, sanitizeHeaderValue(value));
          }
        }
      }
    }

    append(name: string, value: string): void {
      super.append(name, sanitizeHeaderValue(value));
    }

    set(name: string, value: string): void {
      super.set(name, sanitizeHeaderValue(value));
    }
  }

  globalScope.Headers = SafeHeaders;
  globalScope.__HEADERS_PATCHED__ = true;
  console.log('🔧 Headers class patched for ISO-8859-1 compatibility');
}

export class AIService {
  private config: AIConfig | null = null;
  private anthropicClient: Anthropic | null = null;
  private azureProvider: AzureAIProvider;
  private isInitialized = false;
  private activeProvider: AIProvider = 'azure';
  private readonly MAX_RETRIES = 3;
  private readonly RETRY_DELAY_MS = 2000;

  constructor() {
    this.azureProvider = azureAIProvider;
  }

  /**
   * Initialize with configuration
   */
  initialize(config: AIConfig): void {
    this.config = config;
    this.activeProvider = config.provider;

    patchHeadersForBrowser();

    // Initialize Azure provider
    if (config.azure?.endpoint && config.azure?.apiKey) {
      this.azureProvider.initialize(config.azure);
      console.log('✅ Azure AI Foundry provider ready');
    }

    // Initialize Anthropic provider (fallback)
    if (config.anthropic?.apiKey) {
      this.anthropicClient = new Anthropic({
        apiKey: config.anthropic.apiKey,
        dangerouslyAllowBrowser: true,
        timeout: 20 * 60 * 1000,
        maxRetries: 2,
      });
      console.log('✅ Anthropic provider ready (fallback)');
    }

    this.isInitialized = true;
    console.log(`✅ AI Service initialized with ${this.activeProvider} as primary provider`);
  }

  /**
   * Initialize with legacy API key format (backwards compatibility)
   */
  initializeLegacy(apiKey: string): void {
    if (apiKey.startsWith('sk-ant-')) {
      // Direct Anthropic key
      this.initialize({
        provider: 'anthropic',
        anthropic: { apiKey },
      });
    } else {
      // Assume Azure/GitHub token
      this.initialize({
        provider: 'azure',
        azure: {
          endpoint: 'https://models.inference.ai.azure.com',
          apiKey,
        },
      });
    }
  }

  /**
   * Check initialization status
   */
  getInitializationStatus(): boolean {
    return this.isInitialized;
  }

  /**
   * Get active provider
   */
  getActiveProvider(): AIProvider {
    return this.activeProvider;
  }

  /**
   * Set active provider
   */
  setActiveProvider(provider: AIProvider): void {
    if (provider === 'azure' && !this.azureProvider.getInitializationStatus()) {
      throw new Error('Azure provider not initialized');
    }
    if (provider === 'anthropic' && !this.anthropicClient) {
      throw new Error('Anthropic provider not initialized');
    }
    this.activeProvider = provider;
    console.log(`🔄 Switched to ${provider} provider`);
  }

  /**
   * Execute prompt with automatic provider selection and failover
   */
  async execute(options: AIExecuteOptions): Promise<AIResponse> {
    if (!this.isInitialized) {
      throw new Error('AI Service not initialized. Call initialize() first.');
    }

    // Map model to provider-specific model
    const model = this.mapModel(options.model || 'claude-3-5-sonnet-20241022');

    try {
      // Try primary provider
      if (this.activeProvider === 'azure') {
        return await this.executeWithAzure({ ...options, model });
      } else {
        return await this.executeWithAnthropic({ ...options, model });
      }
    } catch (error) {
      console.warn(`⚠️ ${this.activeProvider} provider failed, attempting failover...`);

      // Try fallback provider
      try {
        if (this.activeProvider === 'azure' && this.anthropicClient) {
          console.log('🔄 Failing over to Anthropic...');
          return await this.executeWithAnthropic({ ...options, model: this.mapModelToAnthropic(model) });
        } else if (this.activeProvider === 'anthropic' && this.azureProvider.getInitializationStatus()) {
          console.log('🔄 Failing over to Azure...');
          return await this.executeWithAzure({ ...options, model: this.mapModelToAzure(model) });
        }
      } catch (fallbackError) {
        console.error('❌ Fallback provider also failed:', fallbackError);
      }

      throw error;
    }
  }

  /**
   * Execute with Azure AI Foundry
   */
  private async executeWithAzure(options: AIExecuteOptions): Promise<AIResponse> {
    return this.azureProvider.execute(options);
  }

  /**
   * Execute with direct Anthropic API
   */
  private async executeWithAnthropic(options: AIExecuteOptions): Promise<AIResponse> {
    if (!this.anthropicClient) {
      throw new Error('Anthropic client not initialized');
    }

    const {
      prompt,
      model = 'claude-sonnet-4-5-20250929',
      maxTokens = 8000,
      extendedThinking = false,
      thinkingBudget = 5000,
      stream = false,
      onChunk,
      onThinking,
      tools,
      systemPrompt,
    } = options;

    // Build messages
    const messages: Anthropic.MessageParam[] = [
      { role: 'user', content: prompt },
    ];

    // Build params
    const createParams: Anthropic.MessageCreateParamsNonStreaming = {
      model: this.mapModelToAnthropicFormat(model),
      max_tokens: maxTokens,
      messages,
      ...(systemPrompt && { system: systemPrompt }),
      ...(tools && {
        tools: tools.map((t) => ({
          name: t.name,
          description: t.description,
          input_schema: t.input_schema,
        })),
      }),
    };

    // Add extended thinking
    if (extendedThinking) {
      (createParams as Record<string, unknown>).thinking = {
        type: 'enabled',
        budget_tokens: thinkingBudget,
      };
      console.log(`🧠 Extended Thinking enabled (budget: ${thinkingBudget} tokens)`);
    }

    if (stream) {
      return this.executeAnthropicStreaming(
        { ...createParams, stream: true } as Anthropic.MessageCreateParamsStreaming,
        model,
        onChunk,
        onThinking
      );
    } else {
      return this.executeAnthropicNonStreaming(createParams, model);
    }
  }

  /**
   * Execute non-streaming Anthropic request
   */
  private async executeAnthropicNonStreaming(
    params: Anthropic.MessageCreateParamsNonStreaming,
    model: AIModel
  ): Promise<AIResponse> {
    if (!this.anthropicClient) throw new Error('Not initialized');

    console.log('📤 Sending request to Anthropic...');
    const startTime = Date.now();
    const response = await this.anthropicClient.messages.create(params);
    const duration = Date.now() - startTime;
    console.log(`📥 Response received in ${duration}ms`);

    return this.parseAnthropicResponse(response, model);
  }

  /**
   * Execute streaming Anthropic request
   */
  private async executeAnthropicStreaming(
    params: Anthropic.MessageCreateParamsStreaming,
    model: AIModel,
    onChunk?: (chunk: StreamChunk) => void,
    onThinking?: (thinking: string) => void
  ): Promise<AIResponse> {
    if (!this.anthropicClient) throw new Error('Not initialized');

    console.log('🌊 Starting streaming request to Anthropic...');
    const stream = await this.anthropicClient.messages.stream(params);

    let fullContent = '';
    let fullThinking = '';
    const toolUses: ToolUse[] = [];
    let inputTokens = 0;
    let outputTokens = 0;

    for await (const event of stream) {
      switch (event.type) {
        case 'content_block_delta':
          if (event.delta.type === 'text_delta') {
            fullContent += event.delta.text;
            if (onChunk) {
              onChunk({
                type: 'content',
                content: event.delta.text,
                isComplete: false,
              });
            }
          } else if (event.delta.type === 'thinking_delta') {
            const thinking = (event.delta as Record<string, unknown>).thinking as string;
            if (thinking) {
              fullThinking += thinking;
              if (onThinking) onThinking(thinking);
              if (onChunk) {
                onChunk({
                  type: 'thinking',
                  content: thinking,
                  isComplete: false,
                });
              }
            }
          }
          break;
        case 'message_delta':
          if (event.usage) {
            outputTokens = event.usage.output_tokens;
          }
          break;
      }
    }

    const finalMessage = await stream.finalMessage();
    inputTokens = finalMessage.usage.input_tokens;
    outputTokens = finalMessage.usage.output_tokens;

    // Extract tool uses
    for (const block of finalMessage.content) {
      if (block.type === 'tool_use') {
        toolUses.push({
          type: block.name,
          input: block.input as Record<string, unknown>,
        });
      }
    }

    if (onChunk) {
      onChunk({ type: 'content', content: '', isComplete: true });
    }

    console.log('🏁 Stream completed');

    return {
      content: fullContent,
      thinking: fullThinking || undefined,
      artifacts: this.extractArtifacts(fullContent),
      toolUses: toolUses.length > 0 ? toolUses : undefined,
      usage: { inputTokens, outputTokens },
      provider: 'anthropic',
      model,
    };
  }

  /**
   * Parse Anthropic response
   */
  private parseAnthropicResponse(response: Anthropic.Message, model: AIModel): AIResponse {
    const textBlocks: string[] = [];
    const toolUses: ToolUse[] = [];
    let thinking: string | undefined;

    for (const block of response.content) {
      if (block.type === 'text') {
        textBlocks.push(block.text);
      } else if (block.type === 'tool_use') {
        toolUses.push({
          type: block.name,
          input: block.input as Record<string, unknown>,
        });
      }
    }

    // Check for thinking
    const responseAny = response as Record<string, unknown>;
    if (responseAny.thinking) {
      const thinkingBlocks = responseAny.thinking;
      if (Array.isArray(thinkingBlocks)) {
        thinking = thinkingBlocks
          .filter((b: Record<string, unknown>) => b.type === 'thinking')
          .map((b: Record<string, unknown>) => b.thinking as string)
          .join('\n');
      } else if (typeof thinkingBlocks === 'string') {
        thinking = thinkingBlocks;
      }
    }

    const content = textBlocks.join('\n\n');

    return {
      content,
      thinking,
      artifacts: this.extractArtifacts(content),
      toolUses: toolUses.length > 0 ? toolUses : undefined,
      usage: {
        inputTokens: response.usage.input_tokens,
        outputTokens: response.usage.output_tokens,
      },
      provider: 'anthropic',
      model,
    };
  }

  /**
   * Map generic model name to provider-specific
   */
  private mapModel(model: AIModel): AIModel {
    return model;
  }

  /**
   * Map model to Anthropic format
   */
  private mapModelToAnthropic(model: AIModel): AIModel {
    const mapping: Record<string, AIModel> = {
      'claude-3-5-sonnet-20241022': 'claude-sonnet-4-5-20250929',
      'claude-3-5-haiku-20241022': 'claude-haiku-4-5',
      'claude-3-opus-20240229': 'claude-opus-4-20250514',
    };
    return mapping[model] || model;
  }

  /**
   * Map model to Azure format
   */
  private mapModelToAzure(model: AIModel): AIModel {
    const mapping: Record<string, AIModel> = {
      'claude-sonnet-4-5-20250929': 'claude-3-5-sonnet-20241022',
      'claude-haiku-4-5': 'claude-3-5-haiku-20241022',
      'claude-opus-4-20250514': 'claude-3-opus-20240229',
    };
    return mapping[model] || model;
  }

  /**
   * Map to Anthropic API model format
   */
  private mapModelToAnthropicFormat(model: AIModel): string {
    return model;
  }

  /**
   * Extract artifacts from content
   */
  private extractArtifacts(content: string): Artifact[] {
    const artifacts: Artifact[] = [];
    let index = 0;

    const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
    let match;

    while ((match = codeBlockRegex.exec(content)) !== null) {
      const language = match[1] || 'text';
      const code = match[2].trim();

      if (code.length > 10) {
        artifacts.push({
          id: `artifact-${Date.now()}-${index}`,
          type: this.getArtifactType(language),
          title: `${language.charAt(0).toUpperCase() + language.slice(1)} Code`,
          content: code,
          metadata: { language, lineCount: code.split('\n').length },
          createdAt: Date.now(),
        });
        index++;
      }
    }

    return artifacts;
  }

  /**
   * Get artifact type
   */
  private getArtifactType(language: string): Artifact['type'] {
    const codeLanguages = [
      'javascript', 'typescript', 'python', 'java', 'rust', 'go', 'cpp', 'c',
      'html', 'css', 'jsx', 'tsx', 'ruby', 'php', 'swift', 'kotlin', 'scala',
    ];
    const vizLanguages = ['mermaid', 'graphviz', 'dot', 'plantuml'];
    const dataLanguages = ['json', 'yaml', 'toml', 'xml', 'csv'];

    const lang = language.toLowerCase();
    if (codeLanguages.includes(lang)) return 'code';
    if (vizLanguages.includes(lang)) return 'visualization';
    if (dataLanguages.includes(lang)) return 'data';
    return 'document';
  }

  /**
   * Test connection to active provider
   */
  async testConnection(): Promise<boolean> {
    if (!this.isInitialized) {
      console.error('❌ AI Service not initialized');
      return false;
    }

    try {
      console.log(`🔍 Testing ${this.activeProvider} connection...`);

      const response = await this.execute({
        prompt: 'Reply with exactly "CONNECTION_OK"',
        maxTokens: 50,
      });

      const isOk = response.content.includes('CONNECTION_OK');
      if (isOk) {
        console.log(`✅ ${this.activeProvider} connection successful`);
      } else {
        console.warn(`⚠️ ${this.activeProvider} responded but with unexpected content`);
      }

      return isOk;
    } catch (error) {
      console.error(`❌ ${this.activeProvider} connection test failed:`, error);
      return false;
    }
  }

  /**
   * Get available models for current provider
   */
  getAvailableModels(): AIModel[] {
    if (this.activeProvider === 'azure') {
      return [
        'claude-3-5-sonnet-20241022',
        'claude-3-5-haiku-20241022',
        'claude-3-opus-20240229',
        'gpt-4o',
        'gpt-4o-mini',
      ];
    } else {
      return [
        'claude-sonnet-4-5-20250929',
        'claude-opus-4-20250514',
        'claude-haiku-4-5',
      ];
    }
  }
}

// Export singleton
export const aiService = new AIService();

// Backwards-compatible export (alias for claudeService)
export const claudeService = aiService;
