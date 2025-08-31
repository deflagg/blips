// src/App.jsx
import { useState } from 'react'
import { BrowserRouter, Routes, Route, NavLink } from 'react-router-dom'
import BlipFeed from './components/blipFeed'
import BlipPost from './components/blipPost'
import UsersPage from './components/UsersPage'

function HomeScreen({ onPosted, feedVersion }) {
  return (
    <div className="grid">
      <section className="col col--compose">
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Compose</h2>
            <p className="card-subtitle">Share a quick update.</p>
          </div>
          <div className="card-body">
            <BlipPost onPosted={onPosted} />
          </div>
        </div>
      </section>

      <section className="col col--feed">
        <div className="card">
          <div className="card-header">
            <h2 className="card-title">Recent Blips</h2>
            <p className="card-subtitle">Latest posts, newest first.</p>
          </div>
          <div className="card-body">
            <BlipFeed key={feedVersion} />
          </div>
        </div>
      </section>
    </div>
  )
}

export default function App() {
  const [feedVersion, setFeedVersion] = useState(0)
  const handlePosted = () => setFeedVersion(v => v + 1)

  return (
    <BrowserRouter>
      <div className="app-shell">
        <header className="site-header">
          <div className="container">
            <h1 className="brand">Blips</h1>
            <nav className="nav">
              <NavLink className="nav-link" to="/">Home</NavLink>
              <NavLink className="nav-link" to="/users">Users</NavLink>
              {/* keep other links as needed */}
            </nav>
          </div>
        </header>

        <main className="container">
          <Routes>
            <Route path="/" element={<HomeScreen onPosted={handlePosted} feedVersion={feedVersion} />} />
            <Route path="/users" element={<UsersPage />} />
          </Routes>
        </main>

        <footer className="site-footer">
          <div className="container">
            <small>© {new Date().getFullYear()} Blips — All rights reserved.</small>
          </div>
        </footer>
      </div>
    </BrowserRouter>
  )
}
