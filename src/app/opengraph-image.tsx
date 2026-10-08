import { ImageResponse } from 'next/og'

export const alt =
  'Velvet Grill — Indonesian steakhouse serving steak, burgers, drinks, and desserts for pickup and dine-in.'

export const size = {
  width: 1200,
  height: 630,
}

export const contentType = 'image/png'

// System fonts only — no remote font fetch at render time.
export default function Image() {
  return new ImageResponse(
    (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: '#5a1e2b',
        }}
      >
        <div
          style={{
            width: '92%',
            height: '88%',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            border: '4px solid #7a3342',
            borderRadius: 24,
            color: '#f5f1e8',
          }}
        >
          <div
            style={{
              display: 'flex',
              fontSize: 96,
              fontWeight: 700,
              letterSpacing: 12,
            }}
          >
            VELVET GRILL
          </div>

          <div
            style={{
              display: 'flex',
              marginTop: 28,
              fontSize: 32,
              letterSpacing: 4,
              color: '#e5ded2',
            }}
          >
            Steak · Burgers · Drinks · Desserts
          </div>

          <div
            style={{
              display: 'flex',
              marginTop: 56,
              fontSize: 24,
              letterSpacing: 6,
              color: '#c9a9b0',
            }}
          >
            PICKUP &amp; DINE-IN
          </div>
        </div>
      </div>
    ),
    {
      ...size,
    }
  )
}
