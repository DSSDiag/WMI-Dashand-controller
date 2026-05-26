import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { normalizeDisplayProfile } from './utils'

function getPreviewConfig() {
  if (typeof window === 'undefined') {
    return {
      embeddedPreview: false,
      displayProfile: 'default',
      forceCompact: false,
      initialTab: 'dash',
      label: '',
    }
  }

  const params = new URLSearchParams(window.location.search)
  const preview = params.get('preview')
  const requestedTab = params.get('tab')
  const tab = requestedTab === 'settings' || requestedTab === 'sensor' ? requestedTab : 'dash'
  const displayProfile = normalizeDisplayProfile(params.get('profile'))

  if (preview === 'compact-480x320') {
    return {
      embeddedPreview: true,
      displayProfile: 'generic-ili9486-hat',
      forceCompact: true,
      initialTab: tab,
      label: '480x320 Compact Preview',
    }
  }

  return {
    embeddedPreview: false,
    displayProfile,
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
    displayProfile={previewConfig.displayProfile}
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
