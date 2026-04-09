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

const SCRIPT_TIMEOUT_MS = 30_000

async function runScript(args: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(['bash', SCRIPT, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
    env: { ...process.env },
  })

  let timeoutId: ReturnType<typeof setTimeout>
  const timeout = new Promise<never>((_, reject) => {
    timeoutId = setTimeout(() => {
      proc.kill()
      reject(new Error(`Script timed out after ${SCRIPT_TIMEOUT_MS / 1000}s`))
    }, SCRIPT_TIMEOUT_MS)
  })

  let result: [string, string, number]
  try {
    result = await Promise.race([
      Promise.all([
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
        proc.exited,
      ]),
      timeout,
    ])
  } catch (err) {
    clearTimeout(timeoutId!)
    throw err
  }
  clearTimeout(timeoutId!)
  const [stdout, stderr, exitCode] = result

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
    {
      name: 'find_text',
      description: 'Find text on screen using OCR (tesseract). Returns the center coordinates of each match — use these coordinates to click on UI elements by their label. Much more accurate than guessing coordinates from a screenshot.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          text: { type: 'string', description: 'Text to search for (case-insensitive)' },
          window: { type: 'string', description: 'Window name pattern to search in. Omit for full screen.' },
        },
        required: ['text'],
      },
    },
    {
      name: 'cursor_position',
      description: 'Get the current mouse cursor position on screen.',
      inputSchema: {
        type: 'object' as const,
        properties: {},
      },
    },
    {
      name: 'grid_screenshot',
      description: 'Take a screenshot with a coordinate grid overlay drawn on top. Useful for estimating click coordinates more accurately. Grid lines are labeled with pixel values.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          window: { type: 'string', description: 'Window name pattern to capture. Omit for full screen.' },
          spacing: { type: 'number', description: 'Grid line spacing in pixels. Default: 100.' },
        },
      },
    },
    {
      name: 'crop_region',
      description: 'Take a full-screen screenshot, crop the specified region, and scale it up. Returns the cropped image inline. Useful for inspecting small UI elements or specific screen areas in detail.',
      inputSchema: {
        type: 'object' as const,
        properties: {
          x: { type: 'number', description: 'Left edge of the crop region in screen pixels.' },
          y: { type: 'number', description: 'Top edge of the crop region in screen pixels.' },
          width: { type: 'number', description: 'Width of the crop region in screen pixels.' },
          height: { type: 'number', description: 'Height of the crop region in screen pixels.' },
          scale: { type: 'number', description: 'Scale multiplier for the output image. Default: 2.' },
        },
        required: ['x', 'y', 'width', 'height'],
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
        if (imageBuffer.length === 0) {
          return {
            content: [{ type: 'text', text: `Screenshot file is empty: ${filePath}` }],
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
        if (typeof args?.x !== 'number' || typeof args?.y !== 'number') {
          return { content: [{ type: 'text', text: 'click: x and y are required and must be numbers' }], isError: true }
        }
        const cmdArgs = ['click', String(args.x), String(args.y)]
        if (args?.button) cmdArgs.push('--button', String(args.button))
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'type': {
        if (typeof args?.text !== 'string' || args.text === '') {
          return { content: [{ type: 'text', text: 'type: text is required and must be a non-empty string' }], isError: true }
        }
        const cmdArgs = ['type', args.text]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'key': {
        if (typeof args?.key !== 'string' || args.key === '') {
          return { content: [{ type: 'text', text: 'key: key is required and must be a non-empty string' }], isError: true }
        }
        const cmdArgs = ['key', args.key]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'mouse_move': {
        if (typeof args?.x !== 'number' || typeof args?.y !== 'number') {
          return { content: [{ type: 'text', text: 'mouse_move: x and y are required and must be numbers' }], isError: true }
        }
        const cmdArgs = ['move', String(args.x), String(args.y)]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'drag': {
        if (typeof args?.start_x !== 'number' || typeof args?.start_y !== 'number' ||
            typeof args?.end_x !== 'number' || typeof args?.end_y !== 'number') {
          return { content: [{ type: 'text', text: 'drag: start_x, start_y, end_x, end_y are required and must be numbers' }], isError: true }
        }
        const cmdArgs = ['drag', String(args.start_x), String(args.start_y), String(args.end_x), String(args.end_y)]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'scroll': {
        if (typeof args?.x !== 'number' || typeof args?.y !== 'number') {
          return { content: [{ type: 'text', text: 'scroll: x and y are required and must be numbers' }], isError: true }
        }
        if (typeof args?.direction !== 'string' || args.direction === '') {
          return { content: [{ type: 'text', text: 'scroll: direction is required and must be a non-empty string' }], isError: true }
        }
        const validDirections = ['up', 'down', 'left', 'right']
        if (!validDirections.includes(args.direction)) {
          return { content: [{ type: 'text', text: `scroll: direction must be one of: ${validDirections.join(', ')}` }], isError: true }
        }
        if (args?.clicks !== undefined && typeof args.clicks !== 'number') {
          return { content: [{ type: 'text', text: 'scroll: clicks must be a number' }], isError: true }
        }
        const cmdArgs = ['scroll', String(args.x), String(args.y), args.direction]
        if (args?.clicks !== undefined) cmdArgs.push(String(args.clicks))
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'find_window': {
        if (typeof args?.pattern !== 'string' || args.pattern === '') {
          return { content: [{ type: 'text', text: 'find_window: pattern is required and must be a non-empty string' }], isError: true }
        }
        const cmdArgs = ['find-window', args.pattern, '--json']
        return formatResult(await runScript(cmdArgs))
      }

      case 'focus_window': {
        if (typeof args?.target !== 'string' || args.target === '') {
          return { content: [{ type: 'text', text: 'focus_window: target is required and must be a non-empty string' }], isError: true }
        }
        const cmdArgs = ['focus', args.target, '--json']
        return formatResult(await runScript(cmdArgs))
      }

      case 'computer_status': {
        const cmdArgs = ['status', '--json']
        return formatResult(await runScript(cmdArgs))
      }

      case 'find_text': {
        if (typeof args?.text !== 'string' || args.text === '') {
          return { content: [{ type: 'text', text: 'find_text: text is required and must be a non-empty string' }], isError: true }
        }
        const cmdArgs = ['find-text', args.text]
        if (args?.window) cmdArgs.push('--window', String(args.window))
        cmdArgs.push('--json')
        return formatResult(await runScript(cmdArgs))
      }

      case 'cursor_position': {
        const cmdArgs = ['cursor', '--json']
        return formatResult(await runScript(cmdArgs))
      }

      case 'grid_screenshot': {
        if (args?.spacing !== undefined && typeof args.spacing !== 'number') {
          return { content: [{ type: 'text', text: 'grid_screenshot: spacing must be a number' }], isError: true }
        }
        const cmdArgs = ['grid-screenshot']
        if (args?.window) cmdArgs.push('--window', String(args.window))
        if (args?.spacing !== undefined) cmdArgs.push('--spacing', String(args.spacing))
        cmdArgs.push('--json')
        const result = await runScript(cmdArgs)
        if (result.exitCode !== 0) {
          return { content: [{ type: 'text', text: result.stderr || result.stdout || 'Grid screenshot failed' }], isError: true }
        }
        let filePath: string
        try {
          const parsed = JSON.parse(result.stdout)
          filePath = parsed.path || parsed.file
        } catch {
          filePath = result.stdout
        }
        if (!filePath || !filePath.endsWith('.png')) {
          return { content: [{ type: 'text', text: `Grid screenshot failed: ${result.stderr || result.stdout}` }], isError: true }
        }
        let imageBuffer: Buffer
        try {
          imageBuffer = await readFile(filePath)
        } catch (e: any) {
          return { content: [{ type: 'text', text: `Grid screenshot file not found: ${filePath}\n${e.message}` }], isError: true }
        }
        if (imageBuffer.length === 0) {
          return { content: [{ type: 'text', text: `Grid screenshot file is empty: ${filePath}` }], isError: true }
        }
        const base64 = imageBuffer.toString('base64')
        return {
          content: [
            { type: 'image', data: base64, mimeType: 'image/png' },
            { type: 'text', text: `Grid screenshot saved to: ${filePath}` },
          ],
        }
      }

      case 'crop_region': {
        const cmdArgs = ['zoom', String(args?.x), String(args?.y), String(args?.width), String(args?.height)]
        if (args?.scale !== undefined) cmdArgs.push('--scale', String(args.scale))
        cmdArgs.push('--json')
        const result = await runScript(cmdArgs)
        if (result.exitCode !== 0) {
          return { content: [{ type: 'text', text: result.stderr || result.stdout || 'Crop/zoom failed' }], isError: true }
        }
        let filePath: string
        let outWidth: number | undefined
        let outHeight: number | undefined
        try {
          const parsed = JSON.parse(result.stdout)
          filePath = parsed.path || parsed.file
          outWidth = parsed.width
          outHeight = parsed.height
        } catch {
          filePath = result.stdout
        }
        if (!filePath || !filePath.endsWith('.png')) {
          return { content: [{ type: 'text', text: `Crop/zoom failed: ${result.stderr || result.stdout}` }], isError: true }
        }
        let imageBuffer: Buffer
        try {
          imageBuffer = await readFile(filePath)
        } catch (e: any) {
          return { content: [{ type: 'text', text: `Cropped image not found: ${filePath}\n${e.message}` }], isError: true }
        }
        const base64 = imageBuffer.toString('base64')
        const sizeNote = outWidth && outHeight ? ` (${outWidth}x${outHeight})` : ''
        return {
          content: [
            { type: 'image', data: base64, mimeType: 'image/png' },
            { type: 'text', text: `Cropped region saved to: ${filePath}${sizeNote}` },
          ],
        }
      }

      default:
        return { content: [{ type: 'text', text: `Unknown tool: ${name}` }], isError: true }
    }
  } catch (err: any) {
    const msg = err?.message ?? String(err)
    return {
      content: [{ type: 'text', text: `Error running ${name}: ${msg}\n\nIf dependencies are missing, try running /linux-computer:setup.` }],
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
