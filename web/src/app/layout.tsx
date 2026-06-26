import type { Metadata } from "next";
import { Newsreader, Hanken_Grotesk } from "next/font/google";
import { ClerkProvider } from "@clerk/nextjs";
import "./globals.css";

// Newsreader (serif) for titles/greetings; Hanken Grotesk for body/UI —
// mirrors the iOS PulseFont stack.
const newsreader = Newsreader({
  variable: "--font-newsreader",
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  style: ["normal", "italic"],
});

const hanken = Hanken_Grotesk({
  variable: "--font-hanken",
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
});

export const metadata: Metadata = {
  title: "PulseLoop",
  description: "Your health, everywhere.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <ClerkProvider
      appearance={{
        variables: {
          colorPrimary: "#161616",
          borderRadius: "12px",
          fontFamily: "var(--font-hanken)",
        },
      }}
    >
      <html
        lang="en"
        className={`${newsreader.variable} ${hanken.variable} h-full antialiased`}
      >
        <body className="bg-canvas text-text-primary flex min-h-full flex-col">
          {children}
        </body>
      </html>
    </ClerkProvider>
  );
}
