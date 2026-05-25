cmake_minimum_required(VERSION 3.16)
project(mt5_bridge CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Drogon CONFIG REQUIRED)

add_executable(mt5_bridge
    main.cpp
    MT5Client.cpp
)

target_link_libraries(mt5_bridge PRIVATE Drogon::Drogon)
target_include_directories(mt5_bridge PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
