import type { Metadata, Viewport } from 'next';
import './globals.css';

export const metadata: Metadata = {
  metadataBase: new URL('https://vow.scarce.sh'),
  title: 'Vow — 3-factor authentication for multisig approvals',
  description:
    'An offline approval app for iPad, with a ceremony companion for Mac. Your signature, your security key and your fingerprint, before an approval leaves the device.',
  openGraph: {
    title: 'Vow — 3-factor authentication for multisig approvals',
    description:
      'Your signature, your security key and your fingerprint. Built for iPad. Enforced offline.',
    url: 'https://vow.scarce.sh',
    siteName: 'Vow',
    type: 'website',
  },
  twitter: { card: 'summary_large_image' },
};

export const viewport: Viewport = { themeColor: '#ffffff' };

/** The public site uses local system fonts and makes no third-party requests. */
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
