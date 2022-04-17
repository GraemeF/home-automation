<script lang="ts" context="module">
  import '../app.css';

  export async function load({ fetch }) {
    const url = '/appsettings.json';
    const res = await fetch(url);
    if (res.ok) {
      return {
        props: {
          APPSETTINGS: await res.json(),
        },
      };
    }
    return {
      status: res.status,
      error: new Error('Could not load configuration'),
    };
  }
</script>

<script lang="ts">
  import { appSettingsStore } from '$lib/stores/appsettings';

  export let APPSETTINGS;

  // noinspection JSUnusedAssignment
  $appSettingsStore = APPSETTINGS;
</script>

<slot />
