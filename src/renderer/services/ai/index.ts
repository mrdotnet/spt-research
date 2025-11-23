/**
 * AI Service Module
 * Exports unified AI service with Azure AI Foundry and Anthropic support
 */

export * from './types';
export * from './AzureAIProvider';
export * from './AIService';

// Default export for convenience
export { aiService as default, aiService, claudeService } from './AIService';
