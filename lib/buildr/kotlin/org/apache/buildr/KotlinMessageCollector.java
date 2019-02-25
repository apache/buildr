/* Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with this
 * work for additional information regarding copyright ownership.  The ASF
 * licenses this file to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
 * License for the specific language governing permissions and limitations
 * under the License.
 */


package org.apache.buildr;

import org.jetbrains.kotlin.cli.common.messages.MessageCollector;
import org.jetbrains.kotlin.cli.common.messages.CompilerMessageSeverity;
import org.jetbrains.kotlin.cli.common.messages.CompilerMessageLocation;


public class KotlinMessageCollector implements MessageCollector {

    public void report(CompilerMessageSeverity severity, String message, CompilerMessageLocation location) {
        switch(severity) {
            case ERROR:
            case EXCEPTION:
                System.err.println((location != null ? (location.toString() + " ") : "") + message);
                break;
            default:
                System.out.println((location != null ? (location.toString() + " ") : "") + message);
                break;
        }
    }

    public boolean hasErrors() {
        return false;
    }

    public void clear() {
        // not implemented
    }
}
