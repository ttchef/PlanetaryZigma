#include <vulkan/vulkan.h>
#include <stdbool.h>

typedef struct {
  VkInstance instance;
  VkSurfaceKHR surface;
} GameInit;

typedef struct {
  // TODO(ernesto): put real input state here
  bool up, down, right, left;
} InputState;

typedef struct {
  double dt;
  InputState st;
} GameUpdate;

void engine_init(GameInit init);
void engine_update(GameUpdate state);
void enigne_cleanup(void);
