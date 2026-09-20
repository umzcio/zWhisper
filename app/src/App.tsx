import { Routes, Route } from "react-router";
import Layout from "@/components/Layout";
import Home from "@/pages/Home";
import Modes from "@/pages/Modes";
import History from "@/pages/History";
import Models from "@/pages/Models";
import Vocabulary from "@/pages/Vocabulary";
import Settings from "@/pages/Settings";

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Home />} />
        <Route path="modes" element={<Modes />} />
        <Route path="history" element={<History />} />
        <Route path="models" element={<Models />} />
        <Route path="vocabulary" element={<Vocabulary />} />
        <Route path="settings" element={<Settings />} />
      </Route>
    </Routes>
  );
}
