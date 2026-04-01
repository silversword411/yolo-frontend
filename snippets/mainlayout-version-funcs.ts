// frontend version switching
interface FrontendVersion {
  name: string;
  active: boolean;
}

const frontendVersions = ref<FrontendVersion[]>([]);

async function loadFrontendVersions() {
  try {
    const { data } = await axios.get("/core/frontendversions/");
    frontendVersions.value = data.versions;
  } catch (e) {
    console.error("Failed to load frontend versions", e);
  }
}

async function switchFrontendVersion(versionName: string) {
  try {
    await axios.post("/core/frontendversions/switch/", { version: versionName });
    $q.notify({
      color: "positive",
      message: `Switched to frontend version: ${versionName}`,
      caption: "Reloading page...",
      timeout: 1500,
    });
    setTimeout(() => location.reload(), 1500);
  } catch (e) {
    console.error("Failed to switch frontend version", e);
  }
}

