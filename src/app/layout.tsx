import { Inter as FontSans } from "next/font/google";
import "./globals.css";
import { cn } from "@/lib/utils";
import { Toaster } from "@/components/ui/sonner";
import { ThemeProvider } from "@/components/theme-provider";

const defaultUrl = (process.env.NEXT_PUBLIC_URL as string) || "http://localhost:3000";

const fontSans = FontSans({
    subsets: ["latin"],
    variable: "--font-sans",
});

export const metadata = {
    metadataBase: new URL(defaultUrl),
    title: "Stratarius",
    description: "Belgische loonkost-cascade en loonkloof-analyse voor werkgevers",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
    return (
        <html
            lang="nl"
            suppressHydrationWarning
            className={cn("min-h-screen bg-background font-sans antialiased", fontSans.variable)}
        >
            <body className="bg-background text-foreground">
                <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
                    {children}
                    <Toaster position="top-right" richColors />
                </ThemeProvider>
            </body>
        </html>
    );
}
