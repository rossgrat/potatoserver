"use client";

import { useState } from "react";
import { useSearchParams } from "next/navigation";
import { signIn } from "@/lib/auth-client";
import { getAuthCallbackURL, getSafeRedirect } from "@/lib/auth-redirect";
import { Button } from "@/components/ui/button";
import { Loader } from "lucide-react";

export function SignIn() {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const searchParams = useSearchParams();
  const safeRedirect = getSafeRedirect(searchParams.get("redirect") || "");
  const error =
    message ||
    (searchParams.has("error")
      ? "This CMS is only available to rossgrat. Sign in with that GitHub account."
      : null);

  const handleSignIn = async () => {
    setPending(true);
    setMessage(null);
    try {
      const result = await signIn.social({
        provider: "github",
        callbackURL: getAuthCallbackURL(safeRedirect),
        errorCallbackURL: `/sign-in?redirect=${encodeURIComponent(safeRedirect)}`,
        disableRedirect: true,
      });
      if (result.data?.url) {
        window.location.assign(result.data.url);
        return;
      }
      setMessage("Could not start GitHub sign-in. Please try again.");
    } catch {
      setMessage("Could not start GitHub sign-in. Please try again.");
    }
    setPending(false);
  };

  return (
    <div className="min-h-screen p-4 md:p-6 flex justify-center items-center">
      <div className="sm:max-w-[340px] w-full space-y-6">
        <h1 className="text-lg font-medium tracking-tight text-center">Ross's blog CMS</h1>
        <p className="text-sm text-muted-foreground text-center">Private access for rossgrat.</p>
        {error && (
          <p role="alert" className="text-sm text-destructive">
            {error}
          </p>
        )}
        <Button type="button" className="w-full" onClick={handleSignIn} disabled={pending}>
          Sign in with GitHub
          {pending && <Loader className="size-4 animate-spin" />}
        </Button>
      </div>
    </div>
  );
}
