import Component from '@glimmer/component';
import { modifier } from 'ember-modifier';
import { createShader } from 'shaders/js';

interface ShaderBackgroundSignature {
  Element: HTMLCanvasElement;
  Args: { visible?: boolean };
}

export default class ShaderBackground extends Component<ShaderBackgroundSignature> {
  setupShader = modifier((canvas: HTMLCanvasElement) => {
    let shaderInstance: Awaited<ReturnType<typeof createShader>> | null = null;
    let destroyed = false;

    const init = async () => {
      try {
        if (destroyed) return;

        // Ensure canvas has pixel dimensions before init
        const rect = canvas.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) {
          console.warn(
            '[ShaderBackground] Canvas has zero dimensions, retrying in 100ms',
          );
          await new Promise((r) => setTimeout(r, 100));
          if (destroyed) return;
        }

        console.log(
          '[ShaderBackground] Initializing shader on canvas',
          canvas.getBoundingClientRect(),
        );
        shaderInstance = await createShader(canvas, {
          components: [
            {
              type: 'Aurora',
              id: 'aurora',
              props: {
                colorA: '#7c3aed',
                colorB: '#06b6d4',
                colorC: '#10b981',
                intensity: 20,
                speed: 1.5,
                curtainCount: 3,
                waviness: 30,
                height: 80,
                center: { x: 0.5, y: 0.2 },
              },
            },
          ],
        });
        console.log('[ShaderBackground] Shader initialized successfully');
      } catch (e) {
        console.warn('[ShaderBackground] Failed to initialize shader:', e);
      }
    };

    void init();

    return () => {
      destroyed = true;
      shaderInstance?.destroy();
    };
  });

  <template>
    {{#if this.isVisible}}
      <canvas
        class="shader-canvas pointer-events-none fixed inset-0 -z-10 transition-opacity duration-500"
        style="width: 100vw; height: 100dvh;"
        {{this.setupShader}}
        ...attributes
      ></canvas>
    {{/if}}
  </template>

  get isVisible() {
    return this.args.visible !== false;
  }
}
