/* -*- Mode: C++; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=8 sts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef mozilla_CondVar_h
#define mozilla_CondVar_h

#include "mozilla/BlockingResourceBase.h"
#include "mozilla/PlatformConditionVariable.h"
#include "mozilla/Mutex.h"

#ifdef MOZILLA_INTERNAL_API
#include "GeckoProfiler.h"
#endif  // MOZILLA_INTERNAL_API

namespace mozilla {

/**
 * CondVar
 * Vanilla condition variable.  Please don't use this unless you have a
 * compelling reason --- Monitor provides a simpler API.
 */
class CondVar : BlockingResourceBase {
 public:
  /**
   * CondVar
   *
   * The CALLER owns |aLock|.
   *
   * @param aLock A Mutex to associate with this condition variable.
   * @param aName A name which can reference this monitor
   * @returns If failure, nullptr.
   *          If success, a valid Monitor* which must be destroyed
   *          by Monitor::DestroyMonitor()
   **/
  CondVar(Mutex& aLock, const char* aName)
      : BlockingResourceBase(aName, eCondVar), mLock(&aLock) {
    MOZ_COUNT_CTOR(CondVar);
  }

  /**
   * ~CondVar
   * Clean up after this CondVar, but NOT its associated Mutex.
   **/
  ~CondVar() { MOZ_COUNT_DTOR(CondVar); }

  /**
   * Wait
   * @see prcvar.h
   **/
#ifndef DEBUG
  void Wait() {
#ifdef MOZILLA_INTERNAL_API
    AUTO_PROFILER_THREAD_SLEEP;
#endif //MOZILLA_INTERNAL_API
    mImpl.wait(*mLock);
  }

  CVStatus Wait(TimeDuration aDuration) {
#ifdef MOZILLA_INTERNAL_API
    AUTO_PROFILER_THREAD_SLEEP;
#endif //MOZILLA_INTERNAL_API
    return mImpl.wait_for(*mLock, aDuration);
  }
#else
  // NOTE: debug impl is in BlockingResourceBase.cpp
  void Wait();
  CVStatus Wait(TimeDuration aDuration);
#endif

  /**
   * Notify
   * @see prcvar.h
   **/
  nsresult Notify() {
    mImpl.notify_one();
    return NS_OK;
  }

  /**
   * NotifyAll
   * @see prcvar.h
   **/
  nsresult NotifyAll() {
    mImpl.notify_all();
    return NS_OK;
  }

#ifdef DEBUG
  /**
   * AssertCurrentThreadOwnsMutex
   * @see Mutex::AssertCurrentThreadOwns
   **/
  void AssertCurrentThreadOwnsMutex() { mLock->AssertCurrentThreadOwns(); }

  /**
   * AssertNotCurrentThreadOwnsMutex
   * @see Mutex::AssertNotCurrentThreadOwns
   **/
  void AssertNotCurrentThreadOwnsMutex() {
    mLock->AssertNotCurrentThreadOwns();
  }

#else
  void AssertCurrentThreadOwnsMutex() {}
  void AssertNotCurrentThreadOwnsMutex() {}

#endif  // ifdef DEBUG

 private:
  CondVar();
  CondVar(const CondVar&) = delete;
  CondVar& operator=(const CondVar&) = delete;

  Mutex* mLock;
  detail::ConditionVariableImpl mImpl;
};

}  // namespace mozilla

#endif  // ifndef mozilla_CondVar_h
