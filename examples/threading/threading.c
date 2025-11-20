#include "threading.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Optional: use these functions to add debug or error prints to your
// application
// #define DEBUG_LOG(msg, ...)
#define DEBUG_LOG(msg, ...) printf("threading: " msg "\n", ##__VA_ARGS__)
// #define ERROR_LOG(msg, ...) printf("threading ERROR: " msg "\n",
// ##__VA_ARGS__)

pthread_mutex_t lock;

void* threadfunc(void* thread_param) {
  // TODO: wait, obtain mutex, wait, release mutex as described by thread_data
  // structure hint: use a cast like the one below to obtain thread arguments
  // from your parameter
  // struct thread_data* thread_func_args = (struct thread_data *) thread_param;

  struct thread_data* thread_func_args = (struct thread_data*)thread_param;
  DEBUG_LOG(
      "threadfunc sleeping %d && %d:", thread_func_args->wait_to_obtain_ms,
      thread_func_args->wait_to_release_ms);
  usleep(thread_func_args->wait_to_obtain_ms * 1000);
  DEBUG_LOG("trying to lock ");
  if (pthread_mutex_lock(thread_func_args->lock) != 0) {
    thread_func_args->thread_complete_success = false;
    return thread_param;
  }
  usleep(thread_func_args->wait_to_release_ms * 1000);
  pthread_mutex_unlock(thread_func_args->lock);

  thread_func_args->thread_complete_success = true;
  return thread_param;
}

bool start_thread_obtaining_mutex(pthread_t* thread, pthread_mutex_t* mutex,
                                  int wait_to_obtain_ms,
                                  int wait_to_release_ms) {
  /**
   * TODO: allocate memory for thread_data, setup mutex and wait arguments, pass
   * thread_data to created thread using threadfunc() as entry point.
   *
   * return true if successful.
   *
   * See implementation details in threading.h file comment block
   */
  struct thread_data* thread_data_d = malloc(sizeof(struct thread_data));
  thread_data_d->lock = mutex;
  thread_data_d->thread_complete_success = false;
  thread_data_d->wait_to_obtain_ms = wait_to_obtain_ms;
  thread_data_d->wait_to_release_ms = wait_to_release_ms;

  if (pthread_create(thread, NULL, threadfunc, (void*)thread_data_d) != 0) {
    free(thread_data_d);
    return false;
  }

  return true;
}
