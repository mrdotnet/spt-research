/**
 * AI Provider Types
 * Common interfaces for multi-provider AI support (Azure AI Foundry + Anthropic)
 */

export type AIProvider = 'azure' | 'anthropic';

export type AIModel =
  // Azure AI Foundry Claude models
  | 'claude-3-5-sonnet-20241022'
  | 'claude-3-5-haiku-20241022'
  | 'claude-3-opus-20240229'
  // Azure OpenAI models (fallback)
  | 'gpt-4o'
  | 'gpt-4o-mini'
  | 'o1-preview'
  | 'o1-mini'
  // Direct Anthropic models
  | 'claude-sonnet-4-5-20250929'
  | 'claude-opus-4-20250514'
  | 'claude-haiku-4-5';

export interface AIConfig {
  provider: AIProvider;
  azure?: AzureAIConfig;
  anthropic?: AnthropicConfig;
}

export interface AzureAIConfig {
  endpoint: string;
  apiKey: string;
  deploymentName?: string;
  apiVersion?: string;
}

export interface AnthropicConfig {
  apiKey: string;
}

export interface AIExecuteOptions {
  prompt: string;
  model?: AIModel;
  maxTokens?: number;
  extendedThinking?: boolean;
  thinkingBudget?: number;
  stream?: boolean;
  onChunk?: (chunk: StreamChunk) => void;
  onThinking?: (thinking: string) => void;
  tools?: AITool[];
  systemPrompt?: string;
  temperature?: number;
}

export interface StreamChunk {
  type: 'content' | 'thinking' | 'tool_use';
  content: string;
  isComplete: boolean;
}

export interface AIResponse {
  content: string;
  thinking?: string;
  artifacts?: Artifact[];
  toolUses?: ToolUse[];
  usage?: TokenUsage;
  provider: AIProvider;
  model: string;
}

export interface Artifact {
  id: string;
  stageId?: string;
  type: 'code' | 'document' | 'visualization' | 'data';
  title: string;
  content: string;
  metadata?: Record<string, unknown>;
  createdAt: number;
}

export interface ToolUse {
  type: string;
  input: Record<string, unknown>;
}

export interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  thinkingTokens?: number;
}

export interface AITool {
  name: string;
  description: string;
  input_schema: {
    type: 'object';
    properties: Record<string, unknown>;
    required?: string[];
  };
}

// Model mapping between providers
export const MODEL_MAPPING: Record<string, { azure: AIModel; anthropic: AIModel }> = {
  'sonnet': {
    azure: 'claude-3-5-sonnet-20241022',
    anthropic: 'claude-sonnet-4-5-20250929',
  },
  'haiku': {
    azure: 'claude-3-5-haiku-20241022',
    anthropic: 'claude-haiku-4-5',
  },
  'opus': {
    azure: 'claude-3-opus-20240229',
    anthropic: 'claude-opus-4-20250514',
  },
};

// Default thinking budgets
export const DEFAULT_THINKING_BUDGETS: Record<string, number> = {
  discovering: 12000,
  chasing: 8000,
  solving: 15000,
  challenging: 14000,
  questioning: 6000,
  searching: 8000,
  imagining: 12000,
  building: 15000,
};
