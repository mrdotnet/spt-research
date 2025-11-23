/**
 * Azure AI Foundry Provider
 * Implements AI service using Azure AI inference API with Claude models
 */

import type {
  AIExecuteOptions,
  AIResponse,
  AzureAIConfig,
  StreamChunk,
  Artifact,
  ToolUse,
  AIModel,
} from './types';

export class AzureAIProvider {
  private config: AzureAIConfig | null = null;
  private isInitialized = false;
  private readonly MAX_RETRIES = 3;
  private readonly RETRY_DELAY_MS = 2000;

  /**
   * Initialize Azure AI provider
   */
  initialize(config: AzureAIConfig): void {
    if (!config.endpoint || !config.apiKey) {
      throw new Error('Azure AI endpoint and API key are required');
    }

    this.config = {
      ...config,
      endpoint: config.endpoint.replace(/\/$/, ''), // Remove trailing slash
      apiVersion: config.apiVersion || '2024-05-01-preview',
    };
    this.isInitialized = true;

    console.log('✅ Azure AI Foundry provider initialized');
  }

  /**
   * Check initialization status
   */
  getInitializationStatus(): boolean {
    return this.isInitialized && this.config !== null;
  }

  /**
   * Execute prompt with Azure AI
   */
  async execute(options: AIExecuteOptions): Promise<AIResponse> {
    if (!this.config) {
      throw new Error('Azure AI provider not initialized');
    }

    const {
      prompt,
      model = 'claude-3-5-sonnet-20241022',
      maxTokens = 8000,
      extendedThinking = false,
      thinkingBudget = 5000,
      stream = false,
      onChunk,
      onThinking,
      tools,
      systemPrompt,
      temperature = 0.7,
    } = options;

    // Build request body
    const requestBody = this.buildRequestBody({
      prompt,
      model,
      maxTokens,
      extendedThinking,
      thinkingBudget,
      tools,
      systemPrompt,
      temperature,
    });

    if (stream) {
      return this.executeWithRetry(() =>
        this.executeStreaming(requestBody, model, onChunk, onThinking)
      );
    } else {
      return this.executeNonStreaming(requestBody, model);
    }
  }

  /**
   * Build Azure AI request body
   */
  private buildRequestBody(options: {
    prompt: string;
    model: AIModel;
    maxTokens: number;
    extendedThinking: boolean;
    thinkingBudget: number;
    tools?: AIExecuteOptions['tools'];
    systemPrompt?: string;
    temperature: number;
  }) {
    const messages: Array<{ role: string; content: string }> = [];

    // Add system prompt if provided
    if (options.systemPrompt) {
      messages.push({
        role: 'system',
        content: options.systemPrompt,
      });
    }

    // Add user message
    messages.push({
      role: 'user',
      content: options.prompt,
    });

    const body: Record<string, unknown> = {
      model: options.model,
      messages,
      max_tokens: options.maxTokens,
      temperature: options.temperature,
    };

    // Add extended thinking for Claude models (if supported)
    if (options.extendedThinking && options.model.startsWith('claude')) {
      // Azure AI inference may support this via extra_body
      body.extra_body = {
        thinking: {
          type: 'enabled',
          budget_tokens: options.thinkingBudget,
        },
      };
      console.log(`🧠 Extended Thinking enabled (budget: ${options.thinkingBudget} tokens)`);
    }

    // Add tools if provided
    if (options.tools && options.tools.length > 0) {
      body.tools = options.tools.map((tool) => ({
        type: 'function',
        function: {
          name: tool.name,
          description: tool.description,
          parameters: tool.input_schema,
        },
      }));
    }

    return body;
  }

  /**
   * Execute non-streaming request
   */
  private async executeNonStreaming(
    body: Record<string, unknown>,
    model: AIModel
  ): Promise<AIResponse> {
    if (!this.config) throw new Error('Not initialized');

    const endpoint = this.getEndpoint();
    console.log('📤 Sending request to Azure AI...');
    const startTime = Date.now();

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Azure AI error: ${response.status} - ${error}`);
    }

    const data = await response.json();
    const duration = Date.now() - startTime;
    console.log(`📥 Response received in ${duration}ms`);

    return this.parseResponse(data, model);
  }

  /**
   * Execute streaming request
   */
  private async executeStreaming(
    body: Record<string, unknown>,
    model: AIModel,
    onChunk?: (chunk: StreamChunk) => void,
    onThinking?: (thinking: string) => void
  ): Promise<AIResponse> {
    if (!this.config) throw new Error('Not initialized');

    const endpoint = this.getEndpoint();
    console.log('🌊 Starting streaming request to Azure AI...');

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: this.getHeaders(),
      body: JSON.stringify({ ...body, stream: true }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Azure AI error: ${response.status} - ${error}`);
    }

    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('No response body');
    }

    const decoder = new TextDecoder();
    let fullContent = '';
    let fullThinking = '';
    let inputTokens = 0;
    let outputTokens = 0;

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n').filter((line) => line.startsWith('data: '));

        for (const line of lines) {
          const data = line.slice(6); // Remove 'data: ' prefix
          if (data === '[DONE]') continue;

          try {
            const parsed = JSON.parse(data);

            // Handle content delta
            if (parsed.choices?.[0]?.delta?.content) {
              const content = parsed.choices[0].delta.content;
              fullContent += content;

              if (onChunk) {
                onChunk({
                  type: 'content',
                  content,
                  isComplete: false,
                });
              }
            }

            // Handle thinking (if available in response)
            if (parsed.choices?.[0]?.delta?.thinking) {
              const thinking = parsed.choices[0].delta.thinking;
              fullThinking += thinking;

              if (onThinking) {
                onThinking(thinking);
              }

              if (onChunk) {
                onChunk({
                  type: 'thinking',
                  content: thinking,
                  isComplete: false,
                });
              }
            }

            // Handle usage
            if (parsed.usage) {
              inputTokens = parsed.usage.prompt_tokens || 0;
              outputTokens = parsed.usage.completion_tokens || 0;
            }
          } catch {
            // Skip malformed JSON
          }
        }
      }

      // Signal completion
      if (onChunk) {
        onChunk({
          type: 'content',
          content: '',
          isComplete: true,
        });
      }

      console.log('🏁 Stream completed');
    } finally {
      reader.releaseLock();
    }

    return {
      content: fullContent,
      thinking: fullThinking || undefined,
      artifacts: this.extractArtifacts(fullContent),
      usage: {
        inputTokens,
        outputTokens,
      },
      provider: 'azure',
      model,
    };
  }

  /**
   * Execute with retry on network errors
   */
  private async executeWithRetry(
    operation: () => Promise<AIResponse>,
    attempt: number = 1
  ): Promise<AIResponse> {
    try {
      return await operation();
    } catch (error) {
      const isNetworkError = this.isRetryableError(error);
      const shouldRetry = isNetworkError && attempt < this.MAX_RETRIES;

      if (shouldRetry) {
        const delay = this.RETRY_DELAY_MS * Math.pow(2, attempt - 1);
        console.warn(`⚠️ Network error on attempt ${attempt}/${this.MAX_RETRIES}. Retrying in ${delay}ms...`);
        await new Promise((resolve) => setTimeout(resolve, delay));
        return this.executeWithRetry(operation, attempt + 1);
      }

      throw error;
    }
  }

  /**
   * Check if error is retryable
   */
  private isRetryableError(error: unknown): boolean {
    if (!(error instanceof Error)) return false;

    const errorMessage = error.message.toLowerCase();
    const retryableKeywords = [
      'network error',
      'fetch failed',
      'timeout',
      'connection reset',
      'socket hang up',
      'econnreset',
      '429', // Rate limit
      '503', // Service unavailable
      '502', // Bad gateway
    ];

    return retryableKeywords.some((keyword) => errorMessage.includes(keyword));
  }

  /**
   * Get API endpoint
   */
  private getEndpoint(): string {
    if (!this.config) throw new Error('Not initialized');

    // Azure AI inference endpoint
    return `${this.config.endpoint}/chat/completions`;
  }

  /**
   * Get request headers
   */
  private getHeaders(): Record<string, string> {
    if (!this.config) throw new Error('Not initialized');

    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${this.config.apiKey}`,
    };
  }

  /**
   * Parse Azure AI response
   */
  private parseResponse(data: unknown, model: AIModel): AIResponse {
    const response = data as {
      choices?: Array<{
        message?: {
          content?: string;
          tool_calls?: Array<{
            function: {
              name: string;
              arguments: string;
            };
          }>;
        };
      }>;
      usage?: {
        prompt_tokens?: number;
        completion_tokens?: number;
      };
    };

    const content = response.choices?.[0]?.message?.content || '';
    const toolUses: ToolUse[] = [];

    // Extract tool calls
    const toolCalls = response.choices?.[0]?.message?.tool_calls || [];
    for (const tool of toolCalls) {
      try {
        toolUses.push({
          type: tool.function.name,
          input: JSON.parse(tool.function.arguments),
        });
      } catch {
        // Skip malformed tool calls
      }
    }

    return {
      content,
      artifacts: this.extractArtifacts(content),
      toolUses: toolUses.length > 0 ? toolUses : undefined,
      usage: {
        inputTokens: response.usage?.prompt_tokens || 0,
        outputTokens: response.usage?.completion_tokens || 0,
      },
      provider: 'azure',
      model,
    };
  }

  /**
   * Extract artifacts from content
   */
  private extractArtifacts(content: string): Artifact[] {
    const artifacts: Artifact[] = [];
    let index = 0;

    // Extract code blocks
    const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
    let match;

    while ((match = codeBlockRegex.exec(content)) !== null) {
      const language = match[1] || 'text';
      const code = match[2].trim();

      if (code.length > 10) {
        artifacts.push({
          id: `artifact-${Date.now()}-${index}`,
          type: this.getArtifactType(language),
          title: `${this.capitalizeFirst(language)} Code`,
          content: code,
          metadata: {
            language,
            lineCount: code.split('\n').length,
          },
          createdAt: Date.now(),
        });
        index++;
      }
    }

    return artifacts;
  }

  /**
   * Get artifact type from language
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
   * Capitalize first letter
   */
  private capitalizeFirst(str: string): string {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  /**
   * Test connection
   */
  async testConnection(): Promise<boolean> {
    if (!this.config) {
      console.error('❌ Azure AI provider not initialized');
      return false;
    }

    try {
      console.log('🔍 Testing Azure AI connection...');

      const response = await this.execute({
        prompt: 'Reply with exactly "CONNECTION_OK"',
        model: 'claude-3-5-sonnet-20241022',
        maxTokens: 50,
      });

      const isOk = response.content.includes('CONNECTION_OK');
      if (isOk) {
        console.log('✅ Azure AI connection successful');
      } else {
        console.warn('⚠️ Azure AI responded but with unexpected content');
      }

      return isOk;
    } catch (error) {
      console.error('❌ Azure AI connection test failed:', error);
      return false;
    }
  }
}

// Export singleton
export const azureAIProvider = new AzureAIProvider();
