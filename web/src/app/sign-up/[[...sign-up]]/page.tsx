import { SignUp } from "@clerk/nextjs";

export default function Page() {
  return (
    <main className="flex flex-1 items-center justify-center p-6">
      <SignUp />
    </main>
  );
}
