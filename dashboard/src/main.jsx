import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

function getPreviewConfig() {
  if (typeof window === 'undefined') {
    return {
      embeddedPreview: false,
      forceCompact: false,
      initialTab: 'dash',
      label: '',
    }
  }

  const params = new URLSearchParams(window.location.search)
  const preview = params.get('preview')
  const tab = params.get('tab') === 'settings' ? 'settings' : 'dash'

  if (preview === 'compact-480x320') {
    return {
      embeddedPreview: true,
      forceCompact: true,
      initialTab: tab,
      label: '480x320 Compact Preview',
    }
  }

  return {
    embeddedPreview: false,
    forceCompact: params.get('compact') === '1',
    initialTab: tab,
    label: '',
  }
}

const previewConfig = getPreviewConfig()
const app = (
  <App
    initialTab={previewConfig.initialTab}
    forceCompact={previewConfig.forceCompact}
    embeddedPreview={previewConfig.embeddedPreview}
  />
)

createRoot(document.getElementById('root')).render(
  <StrictMode>
    {previewConfig.embeddedPreview ? (
      <div className="preview-shell">
        <div className="preview-label">{previewConfig.label}</div>
        <div className="preview-frame">
          <div className="preview-screen">
            {app}
          </div>
        </div>
      </div>
    ) : app}
  </StrictMode>,
)
