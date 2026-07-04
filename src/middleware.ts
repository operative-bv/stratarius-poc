import { type NextRequest } from "next/server";
import { validateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await validateSession(request);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - api/* (Vercel Python Serverless Functions — mag niet door Next.js middleware)
     * - images - .svg, .png, .jpg, .jpeg, .gif, .webp
     */
    "/((?!_next/static|_next/image|favicon.ico|api/|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
