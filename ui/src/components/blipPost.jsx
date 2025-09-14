// src/components/BlipPost.jsx
import { useState } from 'react'
import axios from 'axios'

// --- Axios client (same pattern as UsersPage) ---
const API_BASE_URL = (import.meta.env?.VITE_API_BLIP_WRITER || '').replace(/\/+$/, '')

const http = axios.create({
  baseURL: API_BASE_URL || undefined, // falls back to relative requests if unset
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

// Read RU header (Cosmos)
const parseRu = (res) => {
  const h = res?.headers?.['x-ms-request-charge']
  const ru = h ? parseFloat(Array.isArray(h) ? h[0] : h) : 0
  return Number.isFinite(ru) ? ru : 0
}

// Uniform error message extraction
const getErr = (err) =>
  err?.response?.data?.error ||
  err?.response?.data?.message ||
  (typeof err?.response?.data === 'string' ? err.response.data : '') ||
  err.message ||
  'Request failed'

// Minimal API wrapper
const api = {
  // POST /blips expects: { userId, text }
  post: async ({ userId, text }) => {
    const res = await http.post('/blips', { userId, text })
    return { data: res.data, ru: parseRu(res) }
  },
}

// -------- Random blip helpers (module scope so they don't re-create per render) --------
const WORDS = [
  'blip','beam','ping','pulse','flux','echo','spark','nexus','async','queue',
  'azure','aws','cosmos','docv','ocr','model','event','topic','stream','batch',
  'retry','circuit','cache','index','vector','token','gpu','latency','throughput',
  'scale','shard','commit','rollback','log','feed','writer','reader','service',
  'edge','cloud','serverless','gateway','ingest','monitor','metric','trace','id',
  'random','demo','note','update','status','vibe','hello','world','test'
]
const clamp = (n, min, max) => Math.max(min, Math.min(max, n))
const randomInt = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min
const capitalize = (str) => (str ? str[0].toUpperCase() + str.slice(1) : str)
const makeRandomBlip = () => {
  const words = []
  const targetWords = randomInt(5, 28) // ~short tweet
  for (let i = 0; i < targetWords; i++) {
    const w = WORDS[randomInt(0, WORDS.length - 1)]
    words.push(i === 0 ? capitalize(w) : w)
  }
  let s = words.join(' ')
  // a little punctuation sometimes
  const punct = ['.', '!', '…', ' 🚀']
  if (Math.random() < 0.7) s += punct[randomInt(0, punct.length - 1)]
  // keep within 280 chars
  if (s.length > 280) s = s.slice(0, 279) + '…'
  return s
}

export default function BlipPost({ userId, onPosted }) {
  const [text, setText] = useState('')
  const [posting, setPosting] = useState(false)
  const [error, setError] = useState(null)
  const [ok, setOk] = useState(false)
  const [okMsg, setOkMsg] = useState('') // custom success messages
  const [lastRu, setLastRu] = useState(null)

  // Random-post controls
  const [bulkCount, setBulkCount] = useState(5)

  const postBlip = async () => {
    const bodyText = text.trim()
    if (!bodyText || posting) return

    try {
      setPosting(true)
      setError(null)
      setOk(false)
      setOkMsg('')

      const { data, ru } = await api.post({ userId, text: bodyText })
      setLastRu(ru)

      setOk(true)
      setOkMsg('Posted!')
      setText('')

      onPosted?.({ data, ru })
    } catch (e) {
      setError(getErr(e))
    } finally {
      setPosting(false)
    }
  }

  const postRandomBlips = async () => {
    if (posting) return
    const count = clamp(Number(bulkCount) || 1, 1, 100)

    try {
      setPosting(true)
      setError(null)
      setOk(false)
      setOkMsg('')

      let totalRu = 0
      let okCount = 0
      let firstErr = null

      for (let i = 0; i < count; i++) {
        const payload = { userId, text: makeRandomBlip() }
        try {
          const { data, ru } = await api.post(payload)
          totalRu += ru
          okCount += 1
          onPosted?.({ data, ru })
        } catch (e) {
          if (!firstErr) firstErr = getErr(e)
          // continue loop
        }
      }

      setLastRu(totalRu)
      if (okCount === count) {
        setOk(true)
        setOkMsg(`Posted ${okCount} random blip${okCount > 1 ? 's' : ''}!`)
      } else if (okCount > 0) {
        setOk(true)
        setOkMsg(`Posted ${okCount}/${count} random blips.`)
        setError(firstErr || 'Some posts failed.')
      } else {
        setOk(false)
        setError(firstErr || 'Failed to post random blips.')
      }
    } finally {
      setPosting(false)
    }
  }

  const onKeyDown = (e) => {
    if (e.ctrlKey && e.key === 'Enter') postBlip()
  }

  const disabledSingle = posting || !text.trim()
  const disabledBulk = posting || clamp(Number(bulkCount) || 0, 0, 100) < 1

  return (
    <div className="composer">
      <label htmlFor="blip-text" className="label">Your blip</label>
      <textarea
        id="blip-text"
        className="textarea"
        rows={4}
        value={text}
        onChange={(e) => setText(e.target.value)}
        onKeyDown={onKeyDown}
        maxLength={280}
        placeholder="What's your blip? (Ctrl+Enter to post)"
      />

      <div className="composer-actions">
        <button
          type="button"
          className="btn btn-primary"
          onClick={postBlip}
          disabled={disabledSingle}
          aria-busy={posting ? 'true' : 'false'}
        >
          {posting ? 'Posting…' : 'Post blip'}
        </button>

        {/* Random blips: count + button */}
        <div className="inline-field" style={{ display: 'inline-flex', alignItems: 'center', gap: '0.5rem', marginLeft: '0.75rem' }}>
          <label htmlFor="random-count" className="label" style={{ margin: 0 }}>Count</label>
          <input
            id="random-count"
            type="number"
            className="input"
            min={1}
            max={100}
            step={1}
            value={bulkCount}
            disabled={posting}
            onChange={(e) => setBulkCount(e.target.value)}
            style={{ width: '5rem' }}
          />
          <button
            type="button"
            className="btn btn-primary"
            onClick={postRandomBlips}
            disabled={disabledBulk}
            aria-busy={posting ? 'true' : 'false'}
            title="Post N random blips"
          >
            {posting ? 'Posting…' : `Post random`}
          </button>
        </div>

        <span className="muted" style={{ marginLeft: 'auto' }}>
          {text.trim().length}/280
        </span>
      </div>

      {/* RU badge */}
      <div className="metrics right">
        <span className="chip">Last write RU: {lastRu !== null ? lastRu.toFixed(3) : '—'}</span>
      </div>

      {error && <div role="alert" className="alert alert-error">Error: {error}</div>}
      {ok && <div role="status" className="alert alert-success">{okMsg || 'Posted!'}</div>}
    </div>
  )
}
