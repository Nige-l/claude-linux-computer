#!/usr/bin/env bun
/**
 * Linux Computer MCP server for Claude Code.
 *
 * Exposes desktop automation tools (screenshot, click, type, key, etc.)
 * by dispatching to bin/linux-computer.sh. Designed to run under Bun
 * with the MCP SDK's stdio transport.
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from '@modelcontextprotocol/sdk/types.js'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import { readFile } from 'fs/promises'

const __dirname = dirname(fileURLToPath(import.meta.url))
const SCRIPT = join(__dirname, 'bin', 'linux-computer.sh')

// Last-resort safety net — log and keep serving on unhandled errors.
process.on('unhandledRejection', err => {
  process.stderr.write(`linux-computer: unhandled rejection: ${err}\n`)
})
process.on('uncaughtException', err => {
  process.stderr.write(`linux-computer: uncaught exception: ${err}\n`)
})

// ---------------------------------------------------------------------------
// Helper: run the bash script and capture output
// ---------------------------------------------------------------------------

async function runScript(args: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(['bash', SCRIPT, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
    env: { ...process.env },
  })
  const stdout = await new Response(proc.stdout).text()
  const stderr = await new Response(proc.stderr).text()
  const exitCode = await proc.exited
  return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode }
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------

const server = new Server(
  { name: 'linux-computer', version: '0.1.0' },
  { capabilities: { tools: {} } },
)

// ---------------------------------------------------------------------------
// ListTools
// ---------------------------------------------------------------------------

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: 'screenshot',
      description: 'Take a screenshot of the entire screen or a specific window. Returns the image inline.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          window: { type: 'string', description: 'Window name pattern to capture. Omit for full screen.' },
        },
      },
    },
    {
      name: 'click',
      description: 'Click at screen coordinates.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          x: { type: 'number', description: 'X coordinate' },
          y: { type: 'number', description: 'Y coordinate' },
          button: { type: 'string', description: 'Mouse button: 1 (left), 2 (middle), or 3 (right). String names also accepted. Default: left.' },
          window: { type: 'string', description: 'Window name pattern to target.' },
        },
        required: ['x', 'y'],
      },
    },
    {
      name: 'type',
      description: 'Type text using the keyboard.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          text: { type: 'string', description: 'Text to type' },
          window: { type: 'string', description: 'Window name pattern to target.' },
        },
        required: ['text'],
      },
    },
    {
      name: 'key',
      description: 'Press a key or key combination (e.g. Return, ctrl+c, alt+F4).',
      inputSchema: {
        type: 'object' as const,
        properties: {
          key: { type: 'string', description: 'Key or combo to press' },
          window: { type: 'string', description: 'Window name pattern to target.' },
        },
        required: ['key'],
      },
    },
    {
      name: 'mouse_move',
      description: 'Move the mouse cursor to screen coordinates.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          x: { type: 'number', description: 'X coordinate' },
          y: { type: 'number', description: 'Y coordinate' },
          window: { type: 'string', description: 'Window name pattern to target.' },
        },
        required: ['x', 'y'],
      },
    },
    {
      name: 'drag',
      description: 'Drag from one screen coordinate to another.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          start_x: { type: 'number', description: 'Start X coordinate' },
          start_y: { type: 'number', description: 'Start Y coordinate' },
          end_x: { type: 'number', description: 'End X coordinate' },
          end_y: { type: 'number', description: 'End Y coordinate' },
          window: { type: 'string', description: 'Window name pattern to target.' },
        },
        required: ['start_x', 'start_y', 'end_x', 'end_y'],
      },
    },
    {
      name: 'scroll',
      description: 'Scroll at screen coordinates.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          x: { type: 'number', description: 'X coordinate' },
          y: { type: 'number', description: 'Y coordinate' },
          direction: { type: 'string', description: 'Scroll direction: up, down, left, right' },
          clicks: { type: 'number', description: 'Number of scroll clicks. Default: 3.' },
          window: { type: 'string', description: 'Window name pattern to target.' },
        },
        required: ['x', 'y', 'direction'],
      },
    },
    {
      name: 'find_window',
      description: 'Find windows matching a name pattern. Returns JSON with window IDs.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          pattern: { type: 'string', description: 'Window name pattern to search for' },
        },
        required: ['pattern'],
      },
    },
    {
      name: 'focus_window',
      description: 'Focus (activate) a window by name or ID.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          target: { type: 'string', description: 'Window name pattern or window ID to focus' },
        },
        required: ['target'],
      },
    },
    {
      name: 'computer_status',
      description: 'Get display and system status (resolution, running windows, etc.).',
      inputSchema: {
        type: 'object' as const,
        properties: {},
      },
    },
  ],
}))

// ---------------------------------------------------------------------------
// CallTool
// ---------------------------------------------------------------------------

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params

  try {
    switch (name) {
      case 'screenshot': {
        const cmdArgs = ['screenshot']
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        const result = await runScript(cmdArgs)
        if (result.exitCode !== 0) {
          return { content: [{ type: 'text', text: result.stderr || result.stdout || 'Screenshot failed' }], isError: true }
        }
        // Parse the JSON output to get the file path
        let filePath: string
        try {
          const parsed = JSON.parse(result.stdout)
          filePath = parsed.path || parsed.file || parsed.screenshot
        } catch {
          // If not JSON, assume the output is the file path directly
          filePath = result.stdout
        }
        if (!filePath || !filePath.endsWith('.png')) {
          return {
            content: [{ type: 'text', text: `Screenshot failed: ${result.stderr || result.stdout}` }],
            isError: true,
          }
        }
        // Read the PNG file and base64 encode it
        let imageBuffer: Buffer
        try {
          imageBuffer = await readFile(filePath)
        } catch (e: any) {
          return {
            content: [{ type: 'text', text: `Screenshot file not found: ${filePath}\n${e.message}` }],
            isError: true,
          }
        }
        const base64 = imageBuffer.toString('base64')
        return {
          content: [
            { type: 'image', data: base64, mimeType: 'image/png' },
            { type: 'text', text: `Screenshot saved to: ${filePath}` },
          ],
        }
      }

      case 'click': {
        const cmdArgs = ['click', String(args?.x), String(args?.y)]
        if (args?.button) cmdArgs.push('--button', String(args.button))
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'type': {
        const cmdArgs = ['type', String(args?.text)]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'key': {
        const cmdArgs = ['key', String(args?.key)]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'mouse_move': {
        const cmdArgs = ['move', String(args?.x), String(args?.y)]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'drag': {
        const cmdArgs = ['drag', String(args?.start_x), String(args?.start_y), String(args?.end_x), String(args?.end_y)]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'scroll': {
        const cmdArgs = ['scroll', String(args?.x), String(args?.y), String(args?.direction)]
        if (args?.clicks !== undefined) cmdArgs.push(String(args.clicks))
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'find_window': {
        const cmdArgs = ['find-window', String(args?.pattern), '--json']
        return formatResult(await runScript(cmdArgs))
      }

      case 'focus_window': {
        const cmdArgs = ['focus', String(args?.target), '--json']
        return formatResult(await runScript(cmdArgs))
      }

      case 'computer_status': {
        const cmdArgs = ['status', '--json']
        return formatResult(await runScript(cmdArgs))
      }

      default:
        return { content: [{ type: 'text', text: `Unknown tool: ${name}` }], isError: true }
    }
  } catch (err: any) {
    const msg = err?.message ?? String(err)
    return {
      content: [{ type: 'text', text: `Error running ${name}: ${msg}\n\nIf dependencies are missing, try running /computer:setup.` }],
      isError: true,
    }
  }
})

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatResult(result: { stdout: string; stderr: string; exitCode: number }) {
  if (result.exitCode === 0) {
    return { content: [{ type: 'text' as const, text: result.stdout || 'OK' }] }
  }
  return { content: [{ type: 'text' as const, text: result.stderr || result.stdout || 'Command failed' }], isError: true }
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

const transport = new StdioServerTransport()
await server.connect(transport)
