// src/components/GraphPage.jsx
import { useEffect, useRef, useState } from 'react'
import axios from 'axios'
import cytoscape from 'cytoscape'

// --- Axios client (same baseURL pattern)
const API_BASE_URL = (import.meta.env?.VITE_API_BLIP_USER_ADMIN || '').replace(/\/+$/, '')
const http = axios.create({
  baseURL: API_BASE_URL || undefined,
  headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
})

const parseRu = (res) => {
  const h = res?.headers?.['x-ms-request-charge']
  const ru = h ? parseFloat(Array.isArray(h) ? h[0] : h) : 0
  return Number.isFinite(ru) ? ru : 0
}

export default function GraphPage() {
  const containerRef = useRef(null)
  const cyRef = useRef(null)

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [lastRu, setLastRu] = useState(null)
  const [counts, setCounts] = useState({ nodes: 0, edges: 0 })
  const [layoutName, setLayoutName] = useState('cose') // default to force layout

  // Create Cytoscape instance once
  useEffect(() => {
    cyRef.current = cytoscape({
      container: containerRef.current,
      elements: [],
      wheelSensitivity: 0.25,
      style: [
        {
          selector: 'node',
          style: {
            'background-color': '#5a8cf1',
            'label': 'data(label)',
            'font-size': 5,
            'text-valign': 'top',      // <- above node
            'text-halign': 'center',
            'text-margin-y': -6,       // adjust spacing
            'color': '#333',
            'width': 12,
            'height': 12
          }
        },
        {
          selector: 'edge',
          style: {
            'curve-style': 'bezier',
            'width': 1.5,
            'line-color': '#6ea0ff',
            'target-arrow-shape': 'vee',
            'target-arrow-color': '#6ea0ff',
            'arrow-scale': 0.7,
            'opacity': 0.9,
          }
        }
      ],
      layout: { name: layoutName, animate: true, randomize: true, fit: true }
    })

    refreshGraph()
    return () => { cyRef.current?.destroy(); cyRef.current = null }
  }, [])

  // Re-run layout when picker changes
  useEffect(() => {
    if (!cyRef.current) return
    cyRef.current.layout({ name: layoutName, animate: true, randomize: true, fit: true }).run()
  }, [layoutName])

  async function fetchGraph() {
    const res = await http.get('/graph')
    setLastRu(parseRu(res))
    return res.data
  }

  async function refreshGraph() {
    setBusy(true); setError(null)
    try {
      const data = await fetchGraph()
      const els = []
      data.nodes.forEach(n => els.push({ data: { id: n.id, label: n.label } }))
      let i = 0
      data.edges.forEach(e => els.push({ data: { id: `${e.source}->${e.target}#${i++}`, source: e.source, target: e.target } }))

      const cy = cyRef.current
      cy.batch(() => {
        cy.elements().remove()
        cy.add(els)
      })
      setCounts({ nodes: data.nodes.length, edges: data.edges.length })
      cy.layout({ name: layoutName, animate: true, randomize: true, fit: true }).run()
    } catch (e) {
      setError(e?.response?.data?.message || e.message || 'Failed to load graph')
    } finally {
      setBusy(false)
    }
  }

  async function onInitializeData() {
    setBusy(true); setError(null)
    try {
      const res = await http.get('/initializeData')
      setLastRu(parseRu(res))
      await refreshGraph()
    } catch (e) {
      setError(e?.response?.data?.message || e.message || 'Initialize failed')
    } finally {
      setBusy(false)
    }
  }

  async function onDeleteGraph() {
    if (!confirm('Delete the entire graph?')) return
    setBusy(true); setError(null)
    try {
      const res = await http.delete('/DeleteGraph', { params: { batchSize: 1000 } })
      setLastRu(parseRu(res))

      // Clear the canvas immediately for fast feedback
      const cy = cyRef.current
      if (cy) {
        cy.batch(() => cy.elements().remove())
        cy.fit()
      }
      setCounts({ nodes: 0, edges: 0 })

      // Re-query the backend to confirm state (safe even if already empty)
      await refreshGraph()
    } catch (e) {
      setError(e?.response?.data?.message || e.message || 'Delete failed')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="grid grid--single">{/* <- single-column grid (fixes narrow card) */ }
      <section className="col">
        <div className="card">
          <div className="card-header" style={{ display:'flex', alignItems:'center', gap:12 }}>
            <div style={{ flex: 1 }}>
              <h2 className="card-title">User Graph</h2>
              <p className="card-subtitle">All users and their follow relationships.</p>
            </div>

            <div className="metrics right" style={{ display:'flex', alignItems:'center', gap:10 }}>
              <span className="chip">Last RU: {lastRu != null ? lastRu.toFixed(3) : '—'}</span>
              <span className="chip">{counts.nodes} nodes · {counts.edges} edges</span>
            </div>
          </div>

          <div className="card-body" style={{ display:'grid', gap:12 }}>
            <div style={{ display:'flex', gap:8, alignItems:'center', flexWrap:'wrap' }}>
              <button className="btn" onClick={onInitializeData} disabled={busy} title="Seed users and follows">
                {busy ? 'Working…' : 'Initialize data'}
              </button>
              <button
                className="btn btn-danger"
                onClick={onDeleteGraph}
                disabled={busy}
                title="Delete all users and follow edges"
              >
                {busy ? 'Working…' : 'Delete graph'}
              </button>
              <button className="btn" onClick={refreshGraph} disabled={busy}>Refresh</button>
              <button className="btn" onClick={() => cyRef.current?.fit()} disabled={busy}>Fit</button>

              <label className="label" style={{ marginLeft: 12 }}>Layout</label>
              <select
                className="input"
                style={{ width: 160 }}
                value={layoutName}
                onChange={(e) => setLayoutName(e.target.value)}
                disabled={busy}
              >
                <option value="cose">cose (force)</option>
                <option value="circle">circle</option>
                <option value="concentric">concentric</option>
                <option value="grid">grid</option>
                <option value="random">random</option>
              </select>
            </div>

            {/* Graph canvas */}
            <div
              ref={containerRef}
              id="cy"
              style={{
                width: '100%',
                height: 'clamp(420px, 72vh, 900px)',   // responsive height
                background: 'linear-gradient(#f9fbff 0 0) padding-box',
                borderRadius: 12,
                border: '1px solid #e6edf6'
              }}
            />
            {error && (
              <div role="alert" className="alert alert-error">Error: {error}</div>
            )}
          </div>
        </div>
      </section>
    </div>
  )
}
